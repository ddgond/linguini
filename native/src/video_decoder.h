#pragma once

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstddef>
#include <cstdint>

extern "C" {
#include <libavcodec/avcodec.h>
}

namespace linguini {

// One decoded picture as two planes ready for upload: full-resolution luma and
// half-resolution interleaved chroma (NV12 layout). The monitor shader turns
// these into RGB.
struct DecodedFrame {
	int width = 0;
	int height = 0;
	godot::PackedByteArray y;
	godot::PackedByteArray uv;
	bool bt709 = true;
	bool full_range = false;
};

// FFmpeg decoder for H.264 / HEVC / AV1 access units. Tries the platform's
// hardware decoder first (VAAPI, D3D11VA, VideoToolbox) and copies frames back
// to system memory; falls back to software decoding.
class VideoDecoder {
public:
	~VideoDecoder();

	// video_format is one of Limelight's VIDEO_FORMAT_* values.
	bool open(int video_format, int width, int height, bool allow_hw);
	void close();

	// Decodes one Annex-B access unit. `data` must have AV_INPUT_BUFFER_PADDING_SIZE
	// zeroed bytes after `size`. Returns false on a decode error (caller should
	// request an IDR frame). Sets got_frame when `out` holds a new picture.
	bool decode(const uint8_t *data, size_t size, DecodedFrame &out, bool &got_frame);

	godot::String describe() const { return description; }

	static AVCodecID codec_for_format(int video_format);
	static bool can_decode(AVCodecID id);

private:
	bool try_hw(const AVCodec *codec);
	bool convert(const AVFrame *src, DecodedFrame &out);
	static AVPixelFormat get_format(AVCodecContext *ctx, const AVPixelFormat *formats);

	AVCodecContext *ctx = nullptr;
	AVFrame *frame = nullptr;
	AVFrame *sw_frame = nullptr;
	AVPacket *packet = nullptr;
	AVBufferRef *hw_device = nullptr;
	AVPixelFormat hw_format = AV_PIX_FMT_NONE;
	bool warned_format = false;
	godot::String description;
};

} // namespace linguini
