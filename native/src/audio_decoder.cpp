#include "audio_decoder.h"

#include <opus_multistream.h>

#include <algorithm>

using namespace godot;

namespace linguini {

namespace {
// Ring capacity and the latency ceiling: once more than MAX_BUFFERED frames are
// waiting, the oldest are dropped so audio can't drift behind the video.
constexpr size_t RING_FRAMES = 48000 / 2;
constexpr size_t MAX_BUFFERED = 48000 * 6 / 100; // 60 ms
} // namespace

AudioDecoder::~AudioDecoder() {
	close();
}

bool AudioDecoder::open(int sample_rate, int p_channels, int streams, int coupled_streams, int p_samples_per_frame,
		const unsigned char *mapping) {
	close();
	int err = 0;
	decoder = opus_multistream_decoder_create(sample_rate, p_channels, streams, coupled_streams, mapping, &err);
	if (err != OPUS_OK || !decoder) {
		decoder = nullptr;
		return false;
	}
	channels = p_channels;
	samples_per_frame = p_samples_per_frame;
	scratch.resize((size_t)samples_per_frame * channels);

	std::lock_guard lock(mutex);
	ring.assign(RING_FRAMES * 2, 0.0f);
	read_pos = 0;
	buffered = 0;
	return true;
}

void AudioDecoder::close() {
	if (decoder) {
		opus_multistream_decoder_destroy(decoder);
		decoder = nullptr;
	}
	std::lock_guard lock(mutex);
	buffered = 0;
}

void AudioDecoder::decode(const char *data, int length) {
	if (!decoder) {
		return;
	}
	int frames = opus_multistream_decode_float(decoder, (const unsigned char *)data, data ? length : 0,
			scratch.data(), samples_per_frame, 0);
	if (frames <= 0) {
		return;
	}
	if (channels == 2) {
		push(scratch.data(), frames);
		return;
	}
	// Surround or mono: keep front left/right (or duplicate mono).
	std::vector<float> stereo((size_t)frames * 2);
	for (int i = 0; i < frames; i++) {
		const float *s = &scratch[(size_t)i * channels];
		stereo[2 * i] = s[0];
		stereo[2 * i + 1] = channels > 1 ? s[1] : s[0];
	}
	push(stereo.data(), frames);
}

void AudioDecoder::push(const float *pcm, int frames) {
	std::lock_guard lock(mutex);
	if (ring.empty()) {
		return;
	}
	for (int i = 0; i < frames; i++) {
		size_t write_pos = (read_pos + buffered) % RING_FRAMES;
		ring[write_pos * 2] = pcm[2 * i];
		ring[write_pos * 2 + 1] = pcm[2 * i + 1];
		if (buffered < RING_FRAMES) {
			buffered++;
		} else {
			read_pos = (read_pos + 1) % RING_FRAMES;
		}
	}
	if (buffered > MAX_BUFFERED) {
		size_t drop = buffered - MAX_BUFFERED / 2;
		read_pos = (read_pos + drop) % RING_FRAMES;
		buffered -= drop;
	}
}

PackedVector2Array AudioDecoder::pop(int max_frames) {
	PackedVector2Array out;
	std::lock_guard lock(mutex);
	size_t n = std::min(buffered, (size_t)std::max(max_frames, 0));
	out.resize((int64_t)n);
	Vector2 *dst = out.ptrw();
	for (size_t i = 0; i < n; i++) {
		size_t p = (read_pos + i) % RING_FRAMES;
		dst[i] = Vector2(ring[p * 2], ring[p * 2 + 1]);
	}
	read_pos = (read_pos + n) % RING_FRAMES;
	buffered -= n;
	return out;
}

} // namespace linguini
