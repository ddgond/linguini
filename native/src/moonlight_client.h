#pragma once

#include "audio_decoder.h"
#include "video_decoder.h"

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

extern "C" {
#include <client.h>
}

namespace linguini {

// Godot-facing wrapper around libgamestream (pairing, app list, launch) and
// moonlight-common-c (the streaming session).
//
// Host requests block on the network, so they run one at a time on a worker
// thread and report back through signals. moonlight-common-c supports a single
// session per process, so only one MoonlightClient may stream at a time.
class MoonlightClient : public godot::Node {
	GDCLASS(MoonlightClient, godot::Node)

public:
	MoonlightClient();
	~MoonlightClient() override;

	void _process(double delta) override;
	void _exit_tree() override;

	// Host requests (asynchronous).
	void connect_host(const godot::String &address);
	void pair(const godot::String &pin);
	void unpair();
	void fetch_apps();
	void start_stream(int app_id, const godot::Dictionary &options);
	void stop_stream(bool quit_app);

	// Plays a raw H.264/HEVC elementary stream through the same decode path as a
	// live session, looping. Used by tests and for screenshots without a host.
	void play_test_file(const godot::String &path, double fps);

	// Gamepad 0 on the host. Sticks are -32768..32767 (+Y is up), triggers 0..255.
	void send_controller_state(int buttons, int left_trigger, int right_trigger, int left_x, int left_y,
			int right_x, int right_y);

	godot::PackedVector2Array pop_audio(int max_frames);

	godot::Ref<godot::ImageTexture> get_y_texture() const { return y_texture; }
	godot::Ref<godot::ImageTexture> get_uv_texture() const { return uv_texture; }
	bool has_video() const { return video_size.x > 0; }
	godot::Vector2i get_video_size() const { return video_size; }
	bool is_bt709() const { return frame_bt709; }
	bool is_full_range() const { return frame_full_range; }
	bool is_streaming() const { return session_active.load(); }
	godot::String get_decoder_name() const;
	double get_video_fps() const { return video_fps; }

	void set_key_directory(const godot::String &dir) { key_directory = dir; }
	godot::String get_key_directory() const { return key_directory; }

protected:
	static void _bind_methods();

private:
	void enqueue(std::function<void()> job);
	void worker_loop();
	void shutdown();
	godot::Dictionary host_info() const;
	std::string resolved_key_directory() const;
	// Signals raised off the main thread are delivered on it.
	template <typename... Args>
	void emit_deferred(const char *signal, const Args &...args) {
		call_deferred("emit_signal", godot::StringName(signal), godot::Variant(args)...);
	}
	void publish_frame(DecodedFrame &frame);
	void test_loop(std::string path, double fps);

	// moonlight-common-c callbacks (no user pointer; routed through `active`).
	static MoonlightClient *active;
	static int dr_setup(int video_format, int width, int height, int redraw_rate, void *context, int dr_flags);
	static void dr_cleanup();
	static int dr_submit(PDECODE_UNIT unit);
	static int ar_init(int audio_configuration, const POPUS_MULTISTREAM_CONFIGURATION config, void *context,
			int ar_flags);
	static void ar_cleanup();
	static void ar_decode(char *data, int length);
	static void cl_stage_starting(int stage);
	static void cl_stage_failed(int stage, int error_code);
	static void cl_connection_started();
	static void cl_connection_terminated(int error_code);
	static void cl_log(const char *format, ...);

	// Worker thread.
	std::thread worker;
	std::mutex job_mutex;
	std::condition_variable job_cv;
	std::deque<std::function<void()>> jobs;
	bool quitting = false;
	std::atomic<bool> worker_busy{ false };

	// Host state (worker thread only).
	SERVER_DATA server = {};
	std::string server_address;
	bool server_ok = false;
	godot::String key_directory = "user://moonlight";

	// Session state.
	std::atomic<bool> session_active{ false }; // LiStartConnection succeeded, LiStopConnection pending
	std::atomic<bool> input_ready{ false };
	VideoDecoder decoder;
	std::vector<uint8_t> au_buffer;
	AudioDecoder audio;
	std::atomic<int> decoded_frames{ 0 };

	// Test playback.
	std::thread test_thread;
	std::atomic<bool> test_running{ false };

	// Latest decoded frame, handed from the decode thread to _process.
	std::mutex frame_mutex;
	DecodedFrame pending_frame;
	bool frame_pending = false;
	godot::String decoder_name;

	// Main-thread video state.
	godot::Ref<godot::ImageTexture> y_texture;
	godot::Ref<godot::ImageTexture> uv_texture;
	godot::Vector2i video_size;
	bool frame_bt709 = true;
	bool frame_full_range = false;
	double fps_timer = 0.0;
	double video_fps = 0.0;
};

} // namespace linguini
