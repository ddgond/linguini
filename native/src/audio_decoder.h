#pragma once

#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <mutex>
#include <vector>

struct OpusMSDecoder;

namespace linguini {

// Decodes the host's Opus packets and buffers stereo PCM for Godot's
// AudioStreamGenerator, which pulls from the main thread.
class AudioDecoder {
public:
	~AudioDecoder();

	bool open(int sample_rate, int channels, int streams, int coupled_streams, int samples_per_frame,
			const unsigned char *mapping);
	void close();

	// Called on moonlight-common-c's audio thread. A null packet means "lost":
	// Opus conceals it.
	void decode(const char *data, int length);

	// Called on the main thread.
	godot::PackedVector2Array pop(int max_frames);

private:
	void push(const float *pcm, int frames);

	OpusMSDecoder *decoder = nullptr;
	int channels = 0;
	int samples_per_frame = 0;
	std::vector<float> scratch;

	std::mutex mutex;
	std::vector<float> ring; // interleaved L/R
	size_t read_pos = 0;
	size_t buffered = 0; // frames
};

} // namespace linguini
