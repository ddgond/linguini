#include "moonlight_client.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>

extern "C" {
#include <errors.h>
}

using namespace godot;

namespace linguini {

namespace {

constexpr int GAMEPAD_MASK = 0x1;
constexpr int SUPPORTED_BUTTONS = A_FLAG | B_FLAG | X_FLAG | Y_FLAG | UP_FLAG | DOWN_FLAG | LEFT_FLAG |
		RIGHT_FLAG | LB_FLAG | RB_FLAG | PLAY_FLAG | BACK_FLAG | LS_CLK_FLAG | RS_CLK_FLAG | SPECIAL_FLAG;
// Consecutive hardware decode failures before falling back to software.
constexpr int HW_FAILURES_BEFORE_FALLBACK = 5;

String gs_message(int code) {
	if (gs_error) {
		return String::utf8(gs_error);
	}
	switch (code) {
		case GS_OUT_OF_MEMORY:
			return "Out of memory";
		case GS_INVALID:
			return "Unexpected response from host";
		case GS_WRONG_STATE:
			return "Host is in the wrong state";
		case GS_IO_ERROR:
			return "Could not reach host";
		case GS_UNSUPPORTED_VERSION:
			return "Unsupported host version";
		case GS_NOT_SUPPORTED_MODE:
			return "Host does not support this resolution";
		default:
			return "Request failed (" + String::num_int64(code) + ")";
	}
}

} // namespace

MoonlightClient *MoonlightClient::active = nullptr;

// Decoder state shared with the session callbacks. Kept outside the class so
// the callback signatures don't need to reach into private members twice.
static int session_video_format = 0;
static int session_width = 0;
static int session_height = 0;
static int hw_failures = 0;
static bool session_hw = true;
static std::string last_stage_error;

MoonlightClient::MoonlightClient() {
	y_texture.instantiate();
	uv_texture.instantiate();
}

MoonlightClient::~MoonlightClient() {
	shutdown();
}

void MoonlightClient::_bind_methods() {
	ClassDB::bind_method(D_METHOD("connect_host", "address"), &MoonlightClient::connect_host);
	ClassDB::bind_method(D_METHOD("pair", "pin"), &MoonlightClient::pair);
	ClassDB::bind_method(D_METHOD("unpair"), &MoonlightClient::unpair);
	ClassDB::bind_method(D_METHOD("fetch_apps"), &MoonlightClient::fetch_apps);
	ClassDB::bind_method(D_METHOD("start_stream", "app_id", "options"), &MoonlightClient::start_stream);
	ClassDB::bind_method(D_METHOD("stop_stream", "quit_app"), &MoonlightClient::stop_stream);
	ClassDB::bind_method(D_METHOD("play_test_file", "path", "fps"), &MoonlightClient::play_test_file);
	ClassDB::bind_method(D_METHOD("send_controller_state", "buttons", "left_trigger", "right_trigger", "left_x",
								 "left_y", "right_x", "right_y"),
			&MoonlightClient::send_controller_state);
	ClassDB::bind_method(D_METHOD("pop_audio", "max_frames"), &MoonlightClient::pop_audio);
	ClassDB::bind_method(D_METHOD("get_y_texture"), &MoonlightClient::get_y_texture);
	ClassDB::bind_method(D_METHOD("get_uv_texture"), &MoonlightClient::get_uv_texture);
	ClassDB::bind_method(D_METHOD("has_video"), &MoonlightClient::has_video);
	ClassDB::bind_method(D_METHOD("get_video_size"), &MoonlightClient::get_video_size);
	ClassDB::bind_method(D_METHOD("is_bt709"), &MoonlightClient::is_bt709);
	ClassDB::bind_method(D_METHOD("is_full_range"), &MoonlightClient::is_full_range);
	ClassDB::bind_method(D_METHOD("is_streaming"), &MoonlightClient::is_streaming);
	ClassDB::bind_method(D_METHOD("get_decoder_name"), &MoonlightClient::get_decoder_name);
	ClassDB::bind_method(D_METHOD("get_video_fps"), &MoonlightClient::get_video_fps);
	ClassDB::bind_method(D_METHOD("set_key_directory", "dir"), &MoonlightClient::set_key_directory);
	ClassDB::bind_method(D_METHOD("get_key_directory"), &MoonlightClient::get_key_directory);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key_directory"), "set_key_directory", "get_key_directory");

	ADD_SIGNAL(MethodInfo("host_ready", PropertyInfo(Variant::DICTIONARY, "info")));
	ADD_SIGNAL(MethodInfo("paired"));
	ADD_SIGNAL(MethodInfo("apps_ready", PropertyInfo(Variant::ARRAY, "apps")));
	ADD_SIGNAL(MethodInfo("request_failed", PropertyInfo(Variant::STRING, "request"),
			PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("stream_stage", PropertyInfo(Variant::STRING, "stage")));
	ADD_SIGNAL(MethodInfo("stream_started"));
	ADD_SIGNAL(MethodInfo("stream_ended", PropertyInfo(Variant::INT, "error_code"),
			PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("video_size_changed", PropertyInfo(Variant::VECTOR2I, "size")));

	const StringName cls = get_class_static();
	ClassDB::bind_integer_constant(cls, "", "BUTTON_A", A_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_B", B_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_X", X_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_Y", Y_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_DPAD_UP", UP_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_DPAD_DOWN", DOWN_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_DPAD_LEFT", LEFT_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_DPAD_RIGHT", RIGHT_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_LB", LB_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_RB", RB_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_START", PLAY_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_BACK", BACK_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_L3", LS_CLK_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_R3", RS_CLK_FLAG);
	ClassDB::bind_integer_constant(cls, "", "BUTTON_GUIDE", SPECIAL_FLAG);
}

// --- worker thread ---

void MoonlightClient::enqueue(std::function<void()> job) {
	std::lock_guard lock(job_mutex);
	if (quitting) {
		return;
	}
	if (!worker.joinable()) {
		worker = std::thread(&MoonlightClient::worker_loop, this);
	}
	jobs.push_back(std::move(job));
	job_cv.notify_one();
}

void MoonlightClient::worker_loop() {
	while (true) {
		std::function<void()> job;
		{
			std::unique_lock lock(job_mutex);
			job_cv.wait(lock, [this] { return quitting || !jobs.empty(); });
			if (jobs.empty()) {
				return;
			}
			job = std::move(jobs.front());
			jobs.pop_front();
			worker_busy = true;
		}
		job();
		worker_busy = false;
	}
}

void MoonlightClient::shutdown() {
	test_running = false;
	if (test_thread.joinable()) {
		test_thread.join();
	}

	std::unique_lock lock(job_mutex);
	if (quitting) {
		return;
	}
	jobs.clear();
	if (session_active) {
		jobs.push_back([this] {
			LiStopConnection();
			session_active = false;
			active = nullptr;
		});
	}
	quitting = true;
	job_cv.notify_one();
	lock.unlock();

	if (worker.joinable()) {
		// A pairing request blocks until the PIN is entered on the host and
		// libgamestream offers no way to cancel it. Don't hang the app on exit.
		auto idle = [this] {
			std::lock_guard check(job_mutex);
			return jobs.empty() && !worker_busy;
		};
		auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
		while (!idle() && std::chrono::steady_clock::now() < deadline) {
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		if (idle()) {
			worker.join();
		} else {
			worker.detach();
		}
	}
}

void MoonlightClient::_exit_tree() {
	shutdown();
}

std::string MoonlightClient::resolved_key_directory() const {
	String dir = ProjectSettings::get_singleton()->globalize_path(key_directory);
	return std::string(dir.utf8().get_data());
}

Dictionary MoonlightClient::host_info() const {
	Dictionary info;
	info["address"] = String::utf8(server_address.c_str());
	info["paired"] = server.paired;
	info["app_version"] = String::utf8(server.serverInfo.serverInfoAppVersion ? server.serverInfo.serverInfoAppVersion : "");
	info["gpu"] = String::utf8(server.gpuType ? server.gpuType : "");
	info["current_game"] = server.currentGame;
	info["codec_support"] = server.serverInfo.serverCodecModeSupport;
	return info;
}

// --- host requests ---

void MoonlightClient::connect_host(const String &address) {
	std::string addr(address.strip_edges().utf8().get_data());
	std::string keys = resolved_key_directory();
	enqueue([this, addr, keys] {
		if (session_active) {
			emit_deferred("request_failed", "connect", "A stream is already running");
			return;
		}
		// libgamestream keeps pointers into server_address, so it is only
		// replaced here, between requests.
		server = {};
		server_address = addr;
		server_ok = false;
		gs_error = nullptr;
		int ret = gs_init(&server, server_address.data(), 0, keys.c_str(), 0, true);
		if (ret != GS_OK) {
			emit_deferred("request_failed", "connect", gs_message(ret));
			return;
		}
		server_ok = true;
		emit_deferred("host_ready", host_info());
	});
}

void MoonlightClient::pair(const String &pin) {
	std::string p(pin.utf8().get_data());
	enqueue([this, p] {
		if (!server_ok) {
			emit_deferred("request_failed", "pair", "Not connected to a host");
			return;
		}
		gs_error = nullptr;
		std::string pin_copy = p;
		int ret = gs_pair(&server, pin_copy.data());
		if (ret != GS_OK) {
			emit_deferred("request_failed", "pair", gs_message(ret));
			return;
		}
		emit_deferred("paired");
	});
}

void MoonlightClient::unpair() {
	enqueue([this] {
		if (server_ok) {
			gs_unpair(&server);
			server.paired = false;
		}
	});
}

void MoonlightClient::fetch_apps() {
	enqueue([this] {
		if (!server_ok) {
			emit_deferred("request_failed", "apps", "Not connected to a host");
			return;
		}
		gs_error = nullptr;
		PAPP_LIST list = nullptr;
		int ret = gs_applist(&server, &list);
		if (ret != GS_OK) {
			emit_deferred("request_failed", "apps", gs_message(ret));
			return;
		}
		// libgamestream builds the list back to front.
		Array apps;
		while (list) {
			Dictionary app;
			app["id"] = list->id;
			app["name"] = String::utf8(list->name ? list->name : "");
			apps.push_front(app);
			PAPP_LIST next = list->next;
			::free(list->name);
			::free(list);
			list = next;
		}
		emit_deferred("apps_ready", apps);
	});
}

void MoonlightClient::start_stream(int app_id, const Dictionary &options) {
	test_running = false;
	if (test_thread.joinable()) {
		test_thread.join();
	}

	STREAM_CONFIGURATION config;
	LiInitializeStreamConfiguration(&config);
	config.width = options.get("width", 1280);
	config.height = options.get("height", 720);
	config.fps = options.get("fps", 60);
	config.bitrate = options.get("bitrate_kbps", 10000);
	config.packetSize = 1392;
	config.streamingRemotely = STREAM_CFG_AUTO;
	config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
	config.clientRefreshRateX100 = config.fps * 100;
	config.colorSpace = COLORSPACE_REC_709;
	config.colorRange = COLOR_RANGE_LIMITED;
	config.encryptionFlags = ENCFLG_AUDIO;

	String codec = options.get("codec", "auto");
	int formats = 0;
	if ((codec == "auto" || codec == "h264") && VideoDecoder::can_decode(AV_CODEC_ID_H264)) {
		formats |= VIDEO_FORMAT_H264;
	}
	if ((codec == "auto" || codec == "hevc") && VideoDecoder::can_decode(AV_CODEC_ID_HEVC)) {
		formats |= VIDEO_FORMAT_H265;
	}
	if (codec == "av1" && VideoDecoder::can_decode(AV_CODEC_ID_AV1)) {
		formats |= VIDEO_FORMAT_AV1_MAIN8;
	}
	config.supportedVideoFormats = formats;
	session_hw = options.get("hardware_decode", true);

	enqueue([this, app_id, config]() mutable {
		if (!server_ok || !server.paired) {
			emit_deferred("request_failed", "launch", "Not paired with a host");
			return;
		}
		if (session_active) {
			emit_deferred("request_failed", "launch", "A stream is already running");
			return;
		}
		if (config.supportedVideoFormats == 0) {
			emit_deferred("request_failed", "launch", "No usable video decoder");
			return;
		}

		gs_error = nullptr;
		int ret = gs_start_app(&server, &config, app_id, false, false, GAMEPAD_MASK);
		if (ret != GS_OK) {
			emit_deferred("request_failed", "launch", gs_message(ret));
			return;
		}

		CONNECTION_LISTENER_CALLBACKS cl;
		LiInitializeConnectionCallbacks(&cl);
		cl.stageStarting = &MoonlightClient::cl_stage_starting;
		cl.stageFailed = &MoonlightClient::cl_stage_failed;
		cl.connectionStarted = &MoonlightClient::cl_connection_started;
		cl.connectionTerminated = &MoonlightClient::cl_connection_terminated;
		cl.logMessage = &MoonlightClient::cl_log;

		DECODER_RENDERER_CALLBACKS dr;
		LiInitializeVideoCallbacks(&dr);
		dr.setup = &MoonlightClient::dr_setup;
		dr.cleanup = &MoonlightClient::dr_cleanup;
		dr.submitDecodeUnit = &MoonlightClient::dr_submit;

		AUDIO_RENDERER_CALLBACKS ar;
		LiInitializeAudioCallbacks(&ar);
		ar.init = &MoonlightClient::ar_init;
		ar.cleanup = &MoonlightClient::ar_cleanup;
		ar.decodeAndPlaySample = &MoonlightClient::ar_decode;

		active = this;
		last_stage_error.clear();
		ret = LiStartConnection(&server.serverInfo, &config, &cl, &dr, &ar, nullptr, 0, nullptr, 0);
		if (ret != 0) {
			active = nullptr;
			String message = last_stage_error.empty() ? String("Connection failed")
													  : String::utf8(last_stage_error.c_str());
			emit_deferred("request_failed", "launch", message);
			return;
		}
		session_active = true;
	});
}

void MoonlightClient::stop_stream(bool quit_app) {
	enqueue([this, quit_app] {
		if (session_active) {
			input_ready = false;
			LiStopConnection();
			session_active = false;
			active = nullptr;
			emit_deferred("stream_ended", 0, "");
		}
		if (quit_app && server_ok && server.paired) {
			gs_error = nullptr;
			int ret = gs_quit_app(&server);
			if (ret != GS_OK) {
				emit_deferred("request_failed", "quit", gs_message(ret));
			}
		}
	});
}

void MoonlightClient::send_controller_state(int buttons, int left_trigger, int right_trigger, int left_x,
		int left_y, int right_x, int right_y) {
	if (!input_ready) {
		return;
	}
	LiSendMultiControllerEvent(0, GAMEPAD_MASK, buttons, (unsigned char)CLAMP(left_trigger, 0, 255),
			(unsigned char)CLAMP(right_trigger, 0, 255), (short)CLAMP(left_x, -32768, 32767),
			(short)CLAMP(left_y, -32768, 32767), (short)CLAMP(right_x, -32768, 32767),
			(short)CLAMP(right_y, -32768, 32767));
}

PackedVector2Array MoonlightClient::pop_audio(int max_frames) {
	return audio.pop(max_frames);
}

String MoonlightClient::get_decoder_name() const {
	std::lock_guard lock(const_cast<std::mutex &>(frame_mutex));
	return decoder_name;
}

// --- video hand-off ---

void MoonlightClient::publish_frame(DecodedFrame &frame) {
	std::lock_guard lock(frame_mutex);
	pending_frame = frame;
	frame_pending = true;
	decoded_frames++;
}

void MoonlightClient::_process(double delta) {
	DecodedFrame frame;
	bool have = false;
	{
		std::lock_guard lock(frame_mutex);
		if (frame_pending) {
			frame = pending_frame;
			frame_pending = false;
			have = true;
		}
	}

	fps_timer += delta;
	if (fps_timer >= 1.0) {
		video_fps = decoded_frames.exchange(0) / fps_timer;
		fps_timer = 0.0;
	}

	if (!have) {
		return;
	}

	const int cw = (frame.width + 1) / 2;
	const int ch = (frame.height + 1) / 2;
	Ref<Image> y = Image::create_from_data(frame.width, frame.height, false, Image::FORMAT_R8, frame.y);
	Ref<Image> uv = Image::create_from_data(cw, ch, false, Image::FORMAT_RG8, frame.uv);
	Vector2i size(frame.width, frame.height);
	if (size != video_size) {
		y_texture->set_image(y);
		uv_texture->set_image(uv);
		video_size = size;
		emit_signal("video_size_changed", video_size);
	} else {
		y_texture->update(y);
		uv_texture->update(uv);
	}
	frame_bt709 = frame.bt709;
	frame_full_range = frame.full_range;
}

// --- test playback ---

void MoonlightClient::play_test_file(const String &path, double fps) {
	if (session_active) {
		UtilityFunctions::push_error("Linguini: can't play a test file while streaming");
		return;
	}
	test_running = false;
	if (test_thread.joinable()) {
		test_thread.join();
	}
	String abs = ProjectSettings::get_singleton()->globalize_path(path);
	test_running = true;
	test_thread = std::thread(&MoonlightClient::test_loop, this, std::string(abs.utf8().get_data()),
			fps > 0 ? fps : 30.0);
}

void MoonlightClient::test_loop(std::string path, double fps) {
	std::ifstream file(path, std::ios::binary);
	std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	if (data.empty()) {
		UtilityFunctions::push_error("Linguini: can't read test file ", String::utf8(path.c_str()));
		return;
	}

	const bool hevc = path.size() > 5 && (path.rfind(".hevc") == path.size() - 5 || path.rfind(".h265") == path.size() - 5);
	const int format = hevc ? VIDEO_FORMAT_H265 : VIDEO_FORMAT_H264;
	const AVCodecID codec_id = VideoDecoder::codec_for_format(format);

	VideoDecoder test_decoder;
	if (!test_decoder.open(format, 0, 0, true)) {
		return;
	}
	AVCodecParserContext *parser = av_parser_init(codec_id);
	AVCodecContext *parse_ctx = avcodec_alloc_context3(avcodec_find_decoder(codec_id));
	std::vector<uint8_t> packet;
	DecodedFrame frame;
	const auto frame_time = std::chrono::duration<double>(1.0 / fps);
	auto next = std::chrono::steady_clock::now();

	size_t offset = 0;
	while (test_running) {
		uint8_t *out = nullptr;
		int out_size = 0;
		const bool eof = offset >= data.size();
		int used = av_parser_parse2(parser, parse_ctx, &out, &out_size, eof ? nullptr : data.data() + offset,
				eof ? 0 : (int)(data.size() - offset), AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
		offset += used;

		if (out_size > 0) {
			packet.assign(out, out + out_size);
			packet.resize(out_size + AV_INPUT_BUFFER_PADDING_SIZE, 0);
			bool got = false;
			test_decoder.decode(packet.data(), out_size, frame, got);
			if (got) {
				{
					std::lock_guard lock(frame_mutex);
					decoder_name = test_decoder.describe() + " [test file]";
				}
				publish_frame(frame);
				next += std::chrono::duration_cast<std::chrono::steady_clock::duration>(frame_time);
				std::this_thread::sleep_until(next);
			}
		} else if (eof) {
			// Loop: a fresh parser starts cleanly at the first IDR again.
			av_parser_close(parser);
			parser = av_parser_init(codec_id);
			offset = 0;
		}
	}

	av_parser_close(parser);
	avcodec_free_context(&parse_ctx);
}

// --- moonlight-common-c callbacks ---

int MoonlightClient::dr_setup(int video_format, int width, int height, int redraw_rate, void *context,
		int dr_flags) {
	if (!active) {
		return -1;
	}
	session_video_format = video_format;
	session_width = width;
	session_height = height;
	hw_failures = 0;
	if (!active->decoder.open(video_format, width, height, session_hw)) {
		return -1;
	}
	std::lock_guard lock(active->frame_mutex);
	active->decoder_name = active->decoder.describe();
	return 0;
}

void MoonlightClient::dr_cleanup() {
	if (active) {
		active->decoder.close();
	}
}

int MoonlightClient::dr_submit(PDECODE_UNIT unit) {
	MoonlightClient *self = active;
	if (!self) {
		return DR_OK;
	}

	std::vector<uint8_t> &buf = self->au_buffer;
	buf.resize((size_t)unit->fullLength + AV_INPUT_BUFFER_PADDING_SIZE);
	size_t offset = 0;
	for (PLENTRY entry = unit->bufferList; entry; entry = entry->next) {
		memcpy(buf.data() + offset, entry->data, entry->length);
		offset += entry->length;
	}
	memset(buf.data() + offset, 0, AV_INPUT_BUFFER_PADDING_SIZE);

	static thread_local DecodedFrame frame;
	bool got = false;
	if (!self->decoder.decode(buf.data(), offset, frame, got)) {
		if (++hw_failures >= HW_FAILURES_BEFORE_FALLBACK && self->decoder.describe().contains("(software)") == false) {
			UtilityFunctions::print("Linguini: hardware decoding keeps failing, switching to software");
			self->decoder.open(session_video_format, session_width, session_height, false);
			std::lock_guard lock(self->frame_mutex);
			self->decoder_name = self->decoder.describe();
			hw_failures = 0;
		}
		return DR_NEED_IDR;
	}
	hw_failures = 0;
	if (got) {
		self->publish_frame(frame);
	}
	return DR_OK;
}

int MoonlightClient::ar_init(int audio_configuration, const POPUS_MULTISTREAM_CONFIGURATION config, void *context,
		int ar_flags) {
	if (!active) {
		return -1;
	}
	return active->audio.open(config->sampleRate, config->channelCount, config->streams, config->coupledStreams,
				   config->samplesPerFrame, config->mapping)
			? 0
			: -1;
}

void MoonlightClient::ar_cleanup() {
	if (active) {
		active->audio.close();
	}
}

void MoonlightClient::ar_decode(char *data, int length) {
	if (active) {
		active->audio.decode(data, length);
	}
}

void MoonlightClient::cl_stage_starting(int stage) {
	if (active) {
		active->emit_deferred("stream_stage", String(LiGetStageName(stage)));
	}
}

void MoonlightClient::cl_stage_failed(int stage, int error_code) {
	char message[256];
	snprintf(message, sizeof(message), "Failed during %s (error %d)", LiGetStageName(stage), error_code);
	last_stage_error = message;
}

void MoonlightClient::cl_connection_started() {
	MoonlightClient *self = active;
	if (!self) {
		return;
	}
	self->input_ready = true;
	LiSendControllerArrivalEvent(0, GAMEPAD_MASK, LI_CTYPE_XBOX, SUPPORTED_BUTTONS, LI_CCAP_ANALOG_TRIGGERS);
	self->emit_deferred("stream_started");
}

void MoonlightClient::cl_connection_terminated(int error_code) {
	MoonlightClient *self = active;
	if (!self) {
		return;
	}
	self->input_ready = false;
	// LiStopConnection must not run on a moonlight-common-c thread.
	self->enqueue([self, error_code] {
		if (!self->session_active) {
			return;
		}
		LiStopConnection();
		self->session_active = false;
		active = nullptr;
		String message = error_code == ML_ERROR_GRACEFUL_TERMINATION ? String("The host ended the stream")
																	 : "Connection lost (error " + String::num_int64(error_code) + ")";
		self->emit_deferred("stream_ended", error_code, message);
	});
}

void MoonlightClient::cl_log(const char *format, ...) {
	char message[1024];
	va_list args;
	va_start(args, format);
	vsnprintf(message, sizeof(message), format, args);
	va_end(args);
	UtilityFunctions::print("[moonlight] ", String::utf8(message).strip_edges());
}

} // namespace linguini
