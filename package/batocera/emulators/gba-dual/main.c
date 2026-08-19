#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <SDL2/SDL.h>
#include <mgba/flags.h>
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/core/lockstep.h>
#include <mgba/core/thread.h>
#include <mgba/gba/interface.h>
#include <mgba/internal/gba/sio/lockstep.h>
#include <mgba-util/image.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/audio-resampler.h>
#include <mgba-util/vfs.h>

#define GBA_WIDTH 240
#define GBA_HEIGHT 160
#define AUDIO_MIX_FRAMES 2048

enum layout {
	LAYOUT_HORIZONTAL,
	LAYOUT_VERTICAL
};

struct instance {
	struct mCore* core;
	mColor* pixels;
	uint32_t keys;
	// Only used when running a real link-cable session (options.link, interactive mode).
	struct mCoreThread thread;
	struct mLockstepThreadUser lockstepUser;
	struct GBASIOLockstepDriver lockstepDriver;
};

struct options {
	const char* rom1;
	const char* rom2;
	enum layout layout;
	bool link;
	int frames;
	const char* screenshot;
	// SDL joystick index to open for each player; -1 means "auto-pick the
	// first available controller" (used for standalone/dev testing). Set by
	// Batocera's gba-dual configgen generator from each player's
	// Controller.index, so P1/P2 in-game always matches whatever pad ES has
	// assigned to that player slot.
	int controller1;
	int controller2;
};

static void usage(const char* program) {
	fprintf(stderr, "Usage: %s --rom1 ROM --rom2 ROM [--layout horizontal|vertical] [--link|--no-link] "
	                "[--frames N --screenshot PATH] [--controller1 INDEX] [--controller2 INDEX]\n", program);
}

// mGBA's default logger dumps every BIOS call and DMA transfer to stdout;
// silence it so gba-dual's own output stays readable.
static void discard_log(struct mLogger* logger, int category, enum mLogLevel level, const char* format, va_list args) {
	(void) logger;
	(void) category;
	(void) level;
	(void) format;
	(void) args;
}

static struct mLogger nullLogger = { .log = discard_log };

// One resampler per instance, each resampling that core's native-rate audio
// into a per-instance buffer at the shared SDL device rate; the callback then
// sums both into the output. Works for both the threaded (--link) and plain
// synchronous (--no-link) cores: instance->thread.impl is NULL in the latter
// case, and every mCoreSync* call here is a no-op when passed a NULL sync.
struct audio_source {
	struct mAudioBuffer buffer;
	struct mAudioResampler resampler;
};

struct audio_mixer {
	struct instance* instances;
	struct audio_source sources[2];
	SDL_AudioDeviceID device;
	int sampleRate;
};

static void audio_callback(void* userdata, Uint8* stream, int len) {
	struct audio_mixer* mixer = userdata;
	memset(stream, 0, len);
	const int frames = len / (int) (2 * sizeof(int16_t));
	if (frames <= 0 || frames > AUDIO_MIX_FRAMES) {
		return;
	}
	int16_t* out = (int16_t*) stream;
	for (int i = 0; i < 2; ++i) {
		struct instance* instance = &mixer->instances[i];
		struct audio_source* source = &mixer->sources[i];
		struct mCoreSync* sync = instance->thread.impl ? &instance->thread.impl->sync : NULL;
		struct mAudioBuffer* raw = instance->core->getAudioBuffer(instance->core);
		const unsigned sampleRate = instance->core->audioSampleRate(instance->core);
		// Fully paired per source (lock -> resample -> consume) before moving to
		// the next one - never hold one instance's audio lock while touching the
		// other's, for the same reason render_linked() cannot nest video locks.
		mCoreSyncLockAudio(sync);
		if (sync) {
			sync->audioHighWater = frames * 4;
		}
		mAudioResamplerSetSource(&source->resampler, raw, sampleRate, true);
		mAudioResamplerProcess(&source->resampler);
		mCoreSyncConsumeAudio(sync);

		int16_t mixed[AUDIO_MIX_FRAMES * 2];
		const int available = mAudioBufferRead(&source->buffer, mixed, frames);
		for (int f = 0; f < available; ++f) {
			for (int c = 0; c < 2; ++c) {
				const int32_t sum = out[f * 2 + c] + mixed[f * 2 + c];
				out[f * 2 + c] = (int16_t) (sum > INT16_MAX ? INT16_MAX : (sum < INT16_MIN ? INT16_MIN : sum));
			}
		}
	}
}

static bool start_audio(struct audio_mixer* mixer, struct instance* instances) {
	mixer->instances = instances;
	SDL_AudioSpec desired = {0};
	desired.freq = 44100;
	desired.format = AUDIO_S16SYS;
	desired.channels = 2;
	desired.samples = AUDIO_MIX_FRAMES;
	desired.callback = audio_callback;
	desired.userdata = mixer;
	SDL_AudioSpec obtained;
	mixer->device = SDL_OpenAudioDevice(NULL, 0, &desired, &obtained, 0);
	if (mixer->device == 0) {
		fprintf(stderr, "gba-dual: failed to open audio device: %s\n", SDL_GetError());
		return false;
	}
	mixer->sampleRate = obtained.freq;
	for (int i = 0; i < 2; ++i) {
		mAudioBufferInit(&mixer->sources[i].buffer, AUDIO_MIX_FRAMES * 4, 2);
		mAudioResamplerInit(&mixer->sources[i].resampler, mINTERPOLATOR_SINC);
		mAudioResamplerSetDestination(&mixer->sources[i].resampler, &mixer->sources[i].buffer, mixer->sampleRate);
	}
	SDL_PauseAudioDevice(mixer->device, 0);
	return true;
}

static void stop_audio(struct audio_mixer* mixer) {
	if (mixer->device) {
		SDL_CloseAudioDevice(mixer->device);
	}
	for (int i = 0; i < 2; ++i) {
		mAudioBufferDeinit(&mixer->sources[i].buffer);
		mAudioResamplerDeinit(&mixer->sources[i].resampler);
	}
}

static bool parse_options(int argc, char** argv, struct options* options) {
	options->layout = LAYOUT_HORIZONTAL;
	options->link = true;
	options->controller1 = -1;
	options->controller2 = -1;
	for (int i = 1; i < argc; ++i) {
		if (!strcmp(argv[i], "--rom1") && i + 1 < argc) {
			options->rom1 = argv[++i];
		} else if (!strcmp(argv[i], "--rom2") && i + 1 < argc) {
			options->rom2 = argv[++i];
		} else if (!strcmp(argv[i], "--layout") && i + 1 < argc) {
			const char* value = argv[++i];
			if (!strcmp(value, "vertical")) {
				options->layout = LAYOUT_VERTICAL;
			} else if (strcmp(value, "horizontal")) {
				return false;
			}
		} else if (!strcmp(argv[i], "--link")) {
			options->link = true;
		} else if (!strcmp(argv[i], "--no-link")) {
			options->link = false;
		} else if (!strcmp(argv[i], "--frames") && i + 1 < argc) {
			options->frames = atoi(argv[++i]);
		} else if (!strcmp(argv[i], "--screenshot") && i + 1 < argc) {
			options->screenshot = argv[++i];
		} else if (!strcmp(argv[i], "--controller1") && i + 1 < argc) {
			options->controller1 = atoi(argv[++i]);
		} else if (!strcmp(argv[i], "--controller2") && i + 1 < argc) {
			options->controller2 = atoi(argv[++i]);
		} else {
			return false;
		}
	}
	return options->rom1 && options->rom2 && options->frames >= 0;
}

static bool load_instance(struct instance* instance, const char* path) {
	instance->core = mCoreFind(path);
	if (!instance->core || !instance->core->init(instance->core)) {
		return false;
	}
	mCoreInitConfig(instance->core, "gba-dual");
	// mCoreLoadConfig() maps config into core->opts and then calls
	// core->loadConfig(), which sets masterVolume = opts.volume - but only
	// overwrites opts.volume if the config actually has a "volume" key,
	// which ours never does. Left at its zero-init default, that's silence
	// regardless of opts.mute. Seed the same full-volume default mgba's own
	// Qt frontend uses, before config gets a chance to override it.
	instance->core->opts.volume = 0x100;
	instance->core->opts.mute = false;
	mCoreLoadConfig(instance->core);
	if (!mCoreLoadFile(instance->core, path)) {
		instance->core->deinit(instance->core);
		return false;
	}
	instance->pixels = calloc(GBA_WIDTH * GBA_HEIGHT, sizeof(*instance->pixels));
	if (!instance->pixels) {
		instance->core->deinit(instance->core);
		return false;
	}
	instance->core->setVideoBuffer(instance->core, instance->pixels, GBA_WIDTH);
	instance->core->setAudioBufferSize(instance->core, AUDIO_MIX_FRAMES);
	instance->core->reset(instance->core);
	return true;
}

static void destroy_instance(struct instance* instance) {
	if (instance->core) {
		instance->core->deinit(instance->core);
	}
	free(instance->pixels);
}

// Bit positions match enum GBAKey (mgba/internal/gba/input.h): A=0 B=1 Select=2
// Start=3 Right=4 Left=5 Up=6 Down=7 R=8 L=9. The GBA has no X/Y buttons.
static uint32_t map_button(const SDL_ControllerButtonEvent* event) {
	switch (event->button) {
	case SDL_CONTROLLER_BUTTON_A: return 1u << 0;
	case SDL_CONTROLLER_BUTTON_B: return 1u << 1;
	case SDL_CONTROLLER_BUTTON_BACK: return 1u << 2;
	case SDL_CONTROLLER_BUTTON_START: return 1u << 3;
	case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return 1u << 4;
	case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return 1u << 5;
	case SDL_CONTROLLER_BUTTON_DPAD_UP: return 1u << 6;
	case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return 1u << 7;
	case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return 1u << 8;
	case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return 1u << 9;
	default: return 0;
	}
}

// Keyboard fallback so both players can be driven from one keyboard (no
// physical gamepad passthrough into a container). Player 1 uses the arrow
// cluster, player 2 uses WASD; the two sets share no keys.
static uint32_t map_key(SDL_Keycode key, int* player) {
	switch (key) {
	case SDLK_UP: *player = 0; return 1u << 6;
	case SDLK_DOWN: *player = 0; return 1u << 7;
	case SDLK_LEFT: *player = 0; return 1u << 5;
	case SDLK_RIGHT: *player = 0; return 1u << 4;
	case SDLK_z: *player = 0; return 1u << 0;
	case SDLK_x: *player = 0; return 1u << 1;
	case SDLK_RETURN: *player = 0; return 1u << 3;
	case SDLK_RSHIFT: *player = 0; return 1u << 2;
	case SDLK_LEFTBRACKET: *player = 0; return 1u << 9;
	case SDLK_RIGHTBRACKET: *player = 0; return 1u << 8;
	case SDLK_w: *player = 1; return 1u << 6;
	case SDLK_s: *player = 1; return 1u << 7;
	case SDLK_a: *player = 1; return 1u << 5;
	case SDLK_d: *player = 1; return 1u << 4;
	case SDLK_j: *player = 1; return 1u << 0;
	case SDLK_k: *player = 1; return 1u << 1;
	case SDLK_SPACE: *player = 1; return 1u << 3;
	case SDLK_LSHIFT: *player = 1; return 1u << 2;
	case SDLK_u: *player = 1; return 1u << 9;
	case SDLK_i: *player = 1; return 1u << 8;
	default: *player = -1; return 0;
	}
}

static uint32_t* compose(struct instance* first, struct instance* second, enum layout layout, int* outWidth, int* outHeight) {
	const int width = layout == LAYOUT_HORIZONTAL ? GBA_WIDTH * 2 : GBA_WIDTH;
	const int height = layout == LAYOUT_HORIZONTAL ? GBA_HEIGHT : GBA_HEIGHT * 2;
	uint32_t* composite = malloc((size_t) width * (size_t) height * sizeof(*composite));
	if (!composite) {
		return NULL;
	}
	for (int y = 0; y < GBA_HEIGHT; ++y) {
		for (int x = 0; x < GBA_WIDTH; ++x) {
			const uint32_t left = first->pixels[y * GBA_WIDTH + x];
			const uint32_t right = second->pixels[y * GBA_WIDTH + x];
			if (layout == LAYOUT_HORIZONTAL) {
				composite[y * width + x] = left;
				composite[y * width + GBA_WIDTH + x] = right;
			} else {
				composite[y * width + x] = left;
				composite[(GBA_HEIGHT + y) * width + x] = right;
			}
		}
	}
	*outWidth = width;
	*outHeight = height;
	return composite;
}

static void render(struct instance* first, struct instance* second, enum layout layout, SDL_Renderer* renderer, SDL_Texture* texture) {
	int width, height;
	uint32_t* composite = compose(first, second, layout, &width, &height);
	if (!composite) {
		return;
	}
	SDL_UpdateTexture(texture, NULL, composite, width * (int) sizeof(*composite));
	SDL_RenderClear(renderer);
	SDL_RenderCopy(renderer, texture, NULL, NULL);
	SDL_RenderPresent(renderer);
	free(composite);
}

// Counts pixels differing from the top-left one, as a cheap "isn't just a stuck blank frame" signal.
static int count_nonuniform_pixels(const uint32_t* composite, int width, int height) {
	const uint32_t first = composite[0];
	int distinct = 0;
	for (int i = 0; i < width * height; ++i) {
		if (composite[i] != first) {
			++distinct;
		}
	}
	return distinct;
}

static bool save_screenshot(const uint32_t* composite, int width, int height, const char* path) {
	SDL_Surface* surface = SDL_CreateRGBSurfaceWithFormatFrom((void*) composite, width, height, 32, width * 4, SDL_PIXELFORMAT_ABGR8888);
	if (!surface) {
		fprintf(stderr, "gba-dual: failed to wrap framebuffer: %s\n", SDL_GetError());
		return false;
	}
	const bool ok = SDL_SaveBMP(surface, path) == 0;
	if (!ok) {
		fprintf(stderr, "gba-dual: failed to save screenshot: %s\n", SDL_GetError());
	}
	SDL_FreeSurface(surface);
	return ok;
}

// Headless: run a fixed number of frames with no window/display and optionally dump a screenshot.
// This is what lets the ROM smoke test run inside Docker without an X server.
static int run_headless(struct instance* instances, const struct options* options) {
	if (SDL_Init(0) < 0) {
		fprintf(stderr, "gba-dual: SDL init failed: %s\n", SDL_GetError());
		return EXIT_FAILURE;
	}
	for (int i = 0; i < options->frames; ++i) {
		instances[0].core->setKeys(instances[0].core, 0);
		instances[1].core->setKeys(instances[1].core, 0);
		instances[0].core->runFrame(instances[0].core);
		instances[1].core->runFrame(instances[1].core);
	}
	int width = 0, height = 0;
	uint32_t* composite = compose(&instances[0], &instances[1], options->layout, &width, &height);
	int exitCode = EXIT_FAILURE;
	if (composite) {
		const int distinct = count_nonuniform_pixels(composite, width, height);
		printf("gba-dual: ran %d frames, %d/%d pixels differ from the top-left pixel\n", options->frames, distinct, width * height);
		exitCode = EXIT_SUCCESS;
		if (options->screenshot && !save_screenshot(composite, width, height, options->screenshot)) {
			exitCode = EXIT_FAILURE;
		}
		free(composite);
	}
	SDL_Quit();
	return exitCode;
}

// Real GBA link-cable sync (Pokemon trading, Mario Kart multiplayer, etc.) needs
// both cores to run on their own mCoreThread: the GBA SIO multiplayer hardware
// emulation blocks one core's CPU thread mid-instruction until the other side's
// data is ready, which only mgba's GBASIOLockstepCoordinator/Driver + a real
// OS thread per core can do correctly. This is exactly how mgba's own Qt
// frontend (MultiplayerController.cpp) wires up multiplayer.
static bool start_link_session(struct instance instances[2], struct GBASIOLockstepCoordinator* coordinator) {
	GBASIOLockstepCoordinatorInit(coordinator);
	for (int i = 0; i < 2; ++i) {
		// mCoreThreadStart() snapshots core->opts into the thread's sync object,
		// so videoSync/audioSync must be forced on before starting, not after.
		instances[i].core->opts.videoSync = true;
		instances[i].core->opts.audioSync = true;
		instances[i].thread.core = instances[i].core;
		// Each core thread installs its own per-thread logger that bypasses the
		// process-wide default logger, so it must be silenced separately too.
		instances[i].thread.logger.logger = &nullLogger;
		if (!mCoreThreadStart(&instances[i].thread)) {
			return false;
		}
	}
	for (int i = 0; i < 2; ++i) {
		mLockstepThreadUserInit(&instances[i].lockstepUser, &instances[i].thread);
		GBASIOLockstepDriverCreate(&instances[i].lockstepDriver, &instances[i].lockstepUser.d);
	}
	for (int i = 0; i < 2; ++i) {
		GBASIOLockstepCoordinatorAttach(coordinator, &instances[i].lockstepDriver);
		instances[i].core->setPeripheral(instances[i].core, mPERIPH_GBA_LINK_PORT, &instances[i].lockstepDriver.d);
	}
	return true;
}

static void stop_link_session(struct instance instances[2], struct GBASIOLockstepCoordinator* coordinator) {
	for (int i = 0; i < 2; ++i) {
		mCoreThreadEnd(&instances[i].thread);
	}
	for (int i = 0; i < 2; ++i) {
		mCoreThreadJoin(&instances[i].thread);
	}
	for (int i = 0; i < 2; ++i) {
		instances[i].core->setPeripheral(instances[i].core, mPERIPH_GBA_LINK_PORT, NULL);
		GBASIOLockstepCoordinatorDetach(coordinator, &instances[i].lockstepDriver);
	}
	GBASIOLockstepCoordinatorDeinit(coordinator);
}

// Blocks until both threaded cores have a completed frame ready, composites and
// presents it, then releases both so they can render their next frame. Each
// core's mutex must be released (mCoreSyncWaitFrameEnd) before touching the
// other's - mCoreSyncWaitFrameStart holds its sync's mutex locked until then,
// and that mutex is the same one the core thread needs to post its next frame
// (mCoreSyncPostFrame). Holding core A's lock while blocking on core B stalls
// core A's own thread for as long as core B takes, and vice versa next tick -
// two cores serially starving each other's lock collapses throughput to a
// handful of fps. Snapshot each core independently instead, reusing the last
// snapshot for whichever core isn't ready yet so neither side ever blocks the
// other.
static void render_linked(struct instance instances[2], enum layout layout, SDL_Renderer* renderer, SDL_Texture* texture) {
	static mColor snapshot0[GBA_WIDTH * GBA_HEIGHT];
	static mColor snapshot1[GBA_WIDTH * GBA_HEIGHT];

	if (mCoreSyncWaitFrameStart(&instances[0].thread.impl->sync)) {
		memcpy(snapshot0, instances[0].pixels, sizeof(snapshot0));
	}
	mCoreSyncWaitFrameEnd(&instances[0].thread.impl->sync);

	if (mCoreSyncWaitFrameStart(&instances[1].thread.impl->sync)) {
		memcpy(snapshot1, instances[1].pixels, sizeof(snapshot1));
	}
	mCoreSyncWaitFrameEnd(&instances[1].thread.impl->sync);

	struct instance snap0 = { .pixels = snapshot0 };
	struct instance snap1 = { .pixels = snapshot1 };
	render(&snap0, &snap1, layout, renderer, texture);
}

// Safely mutate a running core's keys from the main thread, matching mgba's own
// sdl-events.c pattern (interrupt the core thread, mutate, continue).
static void set_linked_key(struct instance* instance, uint32_t button, bool down) {
	mCoreThreadInterrupt(&instance->thread);
	if (down) {
		instance->core->addKeys(instance->core, button);
	} else {
		instance->core->clearKeys(instance->core, button);
	}
	mCoreThreadContinue(&instance->thread);
}

int main(int argc, char** argv) {
	mLogSetDefaultLogger(&nullLogger);
	struct options options = {0};
	struct instance instances[2] = {0};
	if (!parse_options(argc, argv, &options)) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}
	if (!load_instance(&instances[0], options.rom1) || !load_instance(&instances[1], options.rom2)) {
		fprintf(stderr, "gba-dual: unable to load ROMs\n");
		destroy_instance(&instances[0]);
		destroy_instance(&instances[1]);
		return EXIT_FAILURE;
	}
	if (options.frames > 0) {
		const int exitCode = run_headless(instances, &options);
		destroy_instance(&instances[0]);
		destroy_instance(&instances[1]);
		return exitCode;
	}
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_AUDIO) < 0) {
		fprintf(stderr, "gba-dual: SDL init failed: %s\n", SDL_GetError());
		destroy_instance(&instances[0]);
		destroy_instance(&instances[1]);
		return EXIT_FAILURE;
	}
	const int width = options.layout == LAYOUT_HORIZONTAL ? GBA_WIDTH * 2 : GBA_WIDTH;
	const int height = options.layout == LAYOUT_HORIZONTAL ? GBA_HEIGHT : GBA_HEIGHT * 2;
	SDL_GameController* controllers[2] = {0};
	// event.cbutton.which is an SDL joystick INSTANCE ID, not the enumeration
	// index passed to SDL_GameControllerOpen() - it's only guaranteed to be 0
	// for the very first controller ever opened in the process, so it cannot
	// be compared against a raw 0/1 to identify which player pressed a
	// button. Record each opened controller's real instance ID and match
	// against that instead.
	SDL_JoystickID controllerInstanceIds[2] = { -1, -1 };
	const int requestedIndices[2] = { options.controller1, options.controller2 };
	int autoIndex = 0;
	for (int player = 0; player < 2; ++player) {
		int index = requestedIndices[player];
		if (index < 0) {
			// Auto-pick the next available controller not already claimed by
			// the other player (standalone/dev testing without configgen).
			while (autoIndex < SDL_NumJoysticks() && !SDL_IsGameController(autoIndex)) {
				++autoIndex;
			}
			index = autoIndex < SDL_NumJoysticks() ? autoIndex++ : -1;
		}
		if (index >= 0 && index < SDL_NumJoysticks() && SDL_IsGameController(index)) {
			controllers[player] = SDL_GameControllerOpen(index);
			if (controllers[player]) {
				controllerInstanceIds[player] = SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(controllers[player]));
			}
		}
	}
	SDL_Window* window = SDL_CreateWindow("GBA 2 Players", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, width * 3, height * 3, SDL_WINDOW_RESIZABLE);
	SDL_Renderer* renderer = window ? SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC) : NULL;
	SDL_Texture* texture = renderer ? SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STREAMING, width, height) : NULL;
	if (!window || !renderer || !texture) {
		fprintf(stderr, "gba-dual: SDL video setup failed: %s\n", SDL_GetError());
		SDL_DestroyTexture(texture);
		SDL_DestroyRenderer(renderer);
		SDL_DestroyWindow(window);
		SDL_Quit();
		destroy_instance(&instances[0]);
		destroy_instance(&instances[1]);
		return EXIT_FAILURE;
	}
	struct GBASIOLockstepCoordinator coordinator;
	if (options.link && !start_link_session(instances, &coordinator)) {
		fprintf(stderr, "gba-dual: failed to start link-cable session\n");
		SDL_DestroyTexture(texture);
		SDL_DestroyRenderer(renderer);
		SDL_DestroyWindow(window);
		SDL_Quit();
		destroy_instance(&instances[0]);
		destroy_instance(&instances[1]);
		return EXIT_FAILURE;
	}
	struct audio_mixer mixer = {0};
	const bool audioStarted = start_audio(&mixer, instances);
	if (!audioStarted) {
		fprintf(stderr, "gba-dual: continuing without audio\n");
	}
	bool running = true;
	while (running) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
			if (event.type == SDL_QUIT || (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) {
				running = false;
			} else if (event.type == SDL_CONTROLLERBUTTONDOWN || event.type == SDL_CONTROLLERBUTTONUP) {
				int player = -1;
				if (event.cbutton.which == controllerInstanceIds[0]) player = 0;
				else if (event.cbutton.which == controllerInstanceIds[1]) player = 1;
				if (player < 0) {
					continue;
				}
				const uint32_t button = map_button(&event.cbutton);
				const bool down = event.type == SDL_CONTROLLERBUTTONDOWN;
				if (options.link) set_linked_key(&instances[player], button, down);
				else if (down) instances[player].keys |= button;
				else instances[player].keys &= ~button;
			} else if ((event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) && !event.key.repeat) {
				int player = -1;
				const uint32_t button = map_key(event.key.keysym.sym, &player);
				if (player >= 0) {
					const bool down = event.type == SDL_KEYDOWN;
					if (options.link) set_linked_key(&instances[player], button, down);
					else if (down) instances[player].keys |= button;
					else instances[player].keys &= ~button;
				}
			}
		}
		if (options.link) {
			render_linked(instances, options.layout, renderer, texture);
		} else {
			instances[0].core->setKeys(instances[0].core, instances[0].keys);
			instances[1].core->setKeys(instances[1].core, instances[1].keys);
			instances[0].core->runFrame(instances[0].core);
			instances[1].core->runFrame(instances[1].core);
			render(&instances[0], &instances[1], options.layout, renderer, texture);
		}
	}
	if (audioStarted) {
		stop_audio(&mixer);
	}
	if (options.link) {
		stop_link_session(instances, &coordinator);
	}
	for (int i = 0; i < 2; ++i) {
		if (controllers[i]) {
			SDL_GameControllerClose(controllers[i]);
		}
	}
	SDL_DestroyTexture(texture);
	SDL_DestroyRenderer(renderer);
	SDL_DestroyWindow(window);
	SDL_Quit();
	destroy_instance(&instances[0]);
	destroy_instance(&instances[1]);
	return EXIT_SUCCESS;
}
