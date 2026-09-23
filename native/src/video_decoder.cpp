#include "video_decoder.h"

#include <Limelight.h>

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstring>
#include <thread>

extern "C" {
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
}

using namespace godot;

namespace linguini {

namespace {

const AVHWDeviceType HW_TYPES[] = {
#if defined(_WIN32)
	AV_HWDEVICE_TYPE_D3D11VA,
	AV_HWDEVICE_TYPE_DXVA2,
#elif defined(__APPLE__)
	AV_HWDEVICE_TYPE_VIDEOTOOLBOX,
#else
	AV_HWDEVICE_TYPE_VAAPI,
#endif
};

} // namespace

VideoDecoder::~VideoDecoder() {
	close();
}

AVCodecID VideoDecoder::codec_for_format(int video_format) {
	if (video_format & VIDEO_FORMAT_MASK_H264) {
		return AV_CODEC_ID_H264;
	}
	if (video_format & VIDEO_FORMAT_MASK_H265) {
		return AV_CODEC_ID_HEVC;
	}
	if (video_format & VIDEO_FORMAT_MASK_AV1) {
		return AV_CODEC_ID_AV1;
	}
	return AV_CODEC_ID_NONE;
}

bool VideoDecoder::can_decode(AVCodecID id) {
	return avcodec_find_decoder(id) != nullptr;
}

AVPixelFormat VideoDecoder::get_format(AVCodecContext *ctx, const AVPixelFormat *formats) {
	auto *self = static_cast<VideoDecoder *>(ctx->opaque);
	for (const AVPixelFormat *f = formats; *f != AV_PIX_FMT_NONE; f++) {
		if (*f == self->hw_format) {
			return *f;
		}
	}
	// Hardware surface not offered for this stream; let FFmpeg pick a software format.
	return formats[0];
}

bool VideoDecoder::try_hw(const AVCodec *codec) {
	for (AVHWDeviceType type : HW_TYPES) {
		AVPixelFormat pix_fmt = AV_PIX_FMT_NONE;
		for (int i = 0;; i++) {
			const AVCodecHWConfig *config = avcodec_get_hw_config(codec, i);
			if (!config) {
				break;
			}
			if ((config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX) && config->device_type == type) {
				pix_fmt = config->pix_fmt;
				break;
			}
		}
		if (pix_fmt == AV_PIX_FMT_NONE) {
			continue;
		}
		if (av_hwdevice_ctx_create(&hw_device, type, nullptr, nullptr, 0) < 0) {
			continue;
		}
		hw_format = pix_fmt;
		ctx->hw_device_ctx = av_buffer_ref(hw_device);
		ctx->get_format = &VideoDecoder::get_format;
		description = String(codec->name) + " (" + av_hwdevice_get_type_name(type) + ")";
		return true;
	}
	return false;
}

bool VideoDecoder::open(int video_format, int width, int height, bool allow_hw) {
	close();

	const AVCodec *codec = avcodec_find_decoder(codec_for_format(video_format));
	if (!codec) {
		UtilityFunctions::push_error("Linguini: no FFmpeg decoder for video format ", video_format);
		return false;
	}

	ctx = avcodec_alloc_context3(codec);
	ctx->opaque = this;
	ctx->width = width;
	ctx->height = height;
	ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;

	if (!(allow_hw && try_hw(codec))) {
		// Slice threads keep latency at one frame; frame threads would add several.
		ctx->thread_type = FF_THREAD_SLICE;
		ctx->thread_count = std::clamp((int)std::thread::hardware_concurrency(), 1, 4);
		description = String(codec->name) + " (software)";
	}

	if (avcodec_open2(ctx, codec, nullptr) < 0) {
		UtilityFunctions::push_error("Linguini: failed to open ", description);
		close();
		return false;
	}

	frame = av_frame_alloc();
	sw_frame = av_frame_alloc();
	packet = av_packet_alloc();
	return true;
}

void VideoDecoder::close() {
	if (ctx) {
		avcodec_free_context(&ctx);
	}
	if (hw_device) {
		av_buffer_unref(&hw_device);
	}
	if (frame) {
		av_frame_free(&frame);
	}
	if (sw_frame) {
		av_frame_free(&sw_frame);
	}
	if (packet) {
		av_packet_free(&packet);
	}
	hw_format = AV_PIX_FMT_NONE;
	warned_format = false;
}

bool VideoDecoder::decode(const uint8_t *data, size_t size, DecodedFrame &out, bool &got_frame) {
	got_frame = false;
	if (!ctx) {
		return false;
	}

	packet->data = const_cast<uint8_t *>(data);
	packet->size = (int)size;
	packet->flags = 0;
	int err = avcodec_send_packet(ctx, packet);
	if (err < 0 && err != AVERROR(EAGAIN)) {
		return false;
	}

	while (true) {
		err = avcodec_receive_frame(ctx, frame);
		if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
			break;
		}
		if (err < 0) {
			return false;
		}

		const AVFrame *src = frame;
		if (frame->format == hw_format) {
			av_frame_unref(sw_frame);
			if (av_hwframe_transfer_data(sw_frame, frame, 0) < 0) {
				av_frame_unref(frame);
				return false;
			}
			av_frame_copy_props(sw_frame, frame);
			src = sw_frame;
		}
		if (convert(src, out)) {
			got_frame = true;
		}
		av_frame_unref(frame);
	}
	return true;
}

bool VideoDecoder::convert(const AVFrame *src, DecodedFrame &out) {
	const int w = src->width;
	const int h = src->height;
	const int cw = (w + 1) / 2;
	const int ch = (h + 1) / 2;
	const auto fmt = (AVPixelFormat)src->format;

	const bool nv12 = fmt == AV_PIX_FMT_NV12;
	const bool planar = fmt == AV_PIX_FMT_YUV420P || fmt == AV_PIX_FMT_YUVJ420P;
	if (!nv12 && !planar) {
		if (!warned_format) {
			warned_format = true;
			UtilityFunctions::push_error("Linguini: unsupported decoded pixel format ", av_get_pix_fmt_name(fmt));
		}
		return false;
	}

	out.width = w;
	out.height = h;
	out.bt709 = src->colorspace != AVCOL_SPC_BT470BG && src->colorspace != AVCOL_SPC_SMPTE170M;
	out.full_range = src->color_range == AVCOL_RANGE_JPEG || fmt == AV_PIX_FMT_YUVJ420P;

	out.y.resize((int64_t)w * h);
	uint8_t *y = out.y.ptrw();
	for (int row = 0; row < h; row++) {
		memcpy(y + (size_t)row * w, src->data[0] + (size_t)row * src->linesize[0], w);
	}

	out.uv.resize((int64_t)cw * ch * 2);
	uint8_t *uv = out.uv.ptrw();
	if (nv12) {
		for (int row = 0; row < ch; row++) {
			memcpy(uv + (size_t)row * cw * 2, src->data[1] + (size_t)row * src->linesize[1], (size_t)cw * 2);
		}
	} else {
		for (int row = 0; row < ch; row++) {
			const uint8_t *u = src->data[1] + (size_t)row * src->linesize[1];
			const uint8_t *v = src->data[2] + (size_t)row * src->linesize[2];
			uint8_t *dst = uv + (size_t)row * cw * 2;
			for (int x = 0; x < cw; x++) {
				dst[2 * x] = u[x];
				dst[2 * x + 1] = v[x];
			}
		}
	}
	return true;
}

} // namespace linguini
