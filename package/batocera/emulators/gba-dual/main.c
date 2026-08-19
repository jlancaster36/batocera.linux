#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <SDL2/SDL.h>
#include <mgba/flags.h>
#include <mgba/core/core.h>
#include <mgba-util/image.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/vfs.h>

#define GBA_WIDTH 240
#define GBA_HEIGHT 160
#define AUDIO_FRAMES 4096

enum layout {
	LAYOUT_HORIZONTAL,
	LAYOUT_VERTICAL
};

struct instance {
	struct mCore* core;
	mColor* pixels;
	uint32_t keys;
};

struct options {
	const char* rom1;
	const char* rom2;
	enum layout layout;
	bool link;
	int frames;
	const char* screenshot;
};

static void usage(const char* program) {
	fprintf(stderr, "Usage: %s --rom1 ROM --rom2 ROM [--layout horizontal|vertical] [--link|--no-link] "
	                "[--frames N --screenshot PATH]\n", program);
}

static bool parse_options(int argc, char** argv, struct options* options) {
	options->layout = LAYOUT_HORIZONTAL;
	options->link = true;
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
	instance->core->reset(instance->core);
	return true;
}

static void destroy_instance(struct instance* instance) {
	if (instance->core) {
		instance->core->deinit(instance->core);
	}
	free(instance->pixels);
}

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
	case SDL_CONTROLLER_BUTTON_X: return 1u << 8;
	case SDL_CONTROLLER_BUTTON_Y: return 1u << 9;
	case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return 1u << 10;
	case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return 1u << 11;
	default: return 0;
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

int main(int argc, char** argv) {
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
	bool running = true;
	while (running) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
			if (event.type == SDL_QUIT || (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) {
				running = false;
			} else if (event.type == SDL_CONTROLLERBUTTONDOWN || event.type == SDL_CONTROLLERBUTTONUP) {
				const int player = event.cbutton.which == 0 ? 0 : 1;
				const uint32_t button = map_button(&event.cbutton);
				if (event.type == SDL_CONTROLLERBUTTONDOWN) instances[player].keys |= button;
				else instances[player].keys &= ~button;
			}
		}
		instances[0].core->setKeys(instances[0].core, instances[0].keys);
		instances[1].core->setKeys(instances[1].core, instances[1].keys);
		instances[0].core->runFrame(instances[0].core);
		instances[1].core->runFrame(instances[1].core);
		render(&instances[0], &instances[1], options.layout, renderer, texture);
	}
	SDL_DestroyTexture(texture);
	SDL_DestroyRenderer(renderer);
	SDL_DestroyWindow(window);
	SDL_Quit();
	destroy_instance(&instances[0]);
	destroy_instance(&instances[1]);
	return EXIT_SUCCESS;
}
