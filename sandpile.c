#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))

static void die(const char *s) {
  fprintf(stderr, "%s\n", s);
  exit(1);
}

int N = 801;
int **grid;

// you can also use this function to debug print your sandpile
static void render(char *filename) {
  int chan = 3;
  unsigned char *pixels = (unsigned char *)malloc(N * N * chan * sizeof(char));
  int stride = N * chan;
  if (!pixels)
    die("malloc failed for PNG pixel buffer");
  for (int i = 0; i < N; ++i) {
    for (int j = 0; j < N; ++j) {
      unsigned char r = 0, g = 0, b = 0;
      switch (grid[i][j]) {
      case 0: // obsidian
        r = 15;
        g = 15;
        b = 25;
        break;
      case 1: // electric cyan
        r = 0;
        g = 210;
        b = 255;
        break;
      case 2: // vibrant magenta
        r = 230;
        g = 30;
        b = 130;
        break;
      case 3: // bright gold
        r = 255;
        g = 200;
        b = 0;
        break;
      default: // white
        r = 0;
        g = 0;
        b = 0;
      }

      int pid = (i * N + j) * chan;
      pixels[pid] = r;
      pixels[pid + 1] = g;
      pixels[pid + 2] = b;
    }
  }
  if (stbi_write_png(filename, N, N, chan, pixels, stride)) {
    printf("Successfully saved sandpile identity to: %s\n", filename);
  } else {
    die("Error: stb_image_write failed to save png file\n");
  }
  free(pixels);
}

static void stabilize() {
  // Locals can't be aliased by the int stores into grid, so the compiler can
  // keep them in registers instead of reloading the global N every iteration.
  const int n = N;
  const int half = n / 2;
  const int r2 = half * half;
  // For odd n the pacman is symmetric about row `half`, so only rows
  // 0..half are simulated and the lower half is mirrored at the end.
  const int sym = n % 2;
  const int rows = sym ? half + 1 : n;
  int changed = 0;
  do {
    changed = 0;
    // Toppling row i writes rows i-1..i+1, so rows three apart never touch
    // the same cells. Each phase handles one residue class mod 3 in parallel;
    // the implicit barrier after each phase keeps them apart. The order
    // differs from a serial sweep, but by the abelian property the result
    // is the same.
    for (int phase = 0; phase < 3; ++phase) {
#pragma omp parallel for schedule(static, 1) reduction(| : changed)
      for (int i = phase; i < rows; i += 3) {
        // Row half-1 topples together with its mirror row half+1, and both
        // send a grain into the middle row.
        const int down = (sym && i + 1 == half) ? 2 : 1;
        // Row i of the disk is the interval |j - half| <= r with
        // r = floor(sqrt(r2 - di2)); clip it by the mouth bound.
        const int rem = r2 - (i - half) * (i - half);
        if (rem < 0)
          continue;
        int r = (int)sqrt(rem);
        while (r * r > rem) // fix any floating-point rounding
          r--;
        while ((r + 1) * (r + 1) <= rem)
          r++;
        const int lo = half - r;
        const int hi = MIN(half + r, MAX(i, n - 1 - i));
        for (int j = lo; j <= hi; ++j) {
          if (grid[i][j] < 4)
            continue;
          changed = 1; // topple it
          grid[i][j] -= 4;
          if (i > 0)
            grid[i - 1][j]++;
          if (j > 0)
            grid[i][j - 1]++;
          if (i < n - 1)
            grid[i + 1][j] += down;
          if (j < n - 1)
            grid[i][j + 1]++;
        }
      }
    }
  } while (changed);
  if (sym) // restore the lower half from the upper half
    for (int i = half + 1; i < n; ++i)
      memcpy(grid[i], grid[n - 1 - i], n * sizeof(int));
}

void find_identity() {
  for (int i = 0; i < N; ++i) {
    for (int j = 0; j < N; ++j) {
      grid[i][j] = 6;
    }
  }
  stabilize();
  for (int i = 0; i < N; ++i) {
    for (int j = 0; j < N; ++j) {
      grid[i][j] = 6 - grid[i][j];
    }
  }
  stabilize();
}

int main(int argc, char **argv) {
  if (argc < 2 || argc > 2) {
    fprintf(stderr, "Usage: %s N\n", argv[0]);
    return EXIT_FAILURE;
  }
  char *end;
  uintmax_t parsed = strtoumax(argv[1], &end, 10);
  if (errno || argv[1][0] < '0' || argv[1][0] > '9' || *end || !parsed ||
      parsed > INT32_MAX)
    die("grid size must be a positive int");
  N = (int)parsed;

  grid = (int **)malloc(N * sizeof(int *));
  for (int i = 0; i < N; ++i) {
    grid[i] = (int *)malloc(N * sizeof(int));
  }

  find_identity();

  render("identity.png");
  for (int i = 0; i < N; ++i) {
    free(grid[i]);
  }
  free(grid);
  return EXIT_SUCCESS;
}
