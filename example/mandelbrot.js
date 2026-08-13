/**
 * Mandelbrot set, ASCII art version
 */
function drawMandelbrot() {
  const width = 70; // Drawing width
  const height = 40; // Drawing height
  const maxIteration = 50; // Maximum number of iterations

  // Characters for ASCII art (darker characters represent points inside the set)
  const chars = " .:-=+*#%@";

  let result = "";

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // Convert screen coordinates to coordinates on the complex plane (-2.0 < re < 1.0, -1.0 < im < 1.0)
      let c_re = (x - width / 1.5) * 3.0 / width;
      let c_im = (y - height / 2) * 2.0 / height;

      let z_re = 0;
      let z_im = 0;
      let iteration = 0;

      // Mandelbrot iteration: z = z^2 + c
      while (z_re * z_re + z_im * z_im <= 4 && iteration < maxIteration) {
        let next_re = z_re * z_re - z_im * z_im + c_re;
        let next_im = 2 * z_re * z_im + c_im;
        z_re = next_re;
        z_im = next_im;
        iteration++;
      }

      // Choose a character based on the rate of divergence
      if (iteration === maxIteration) {
        result += "@"; // Inside the set
      } else {
        result += chars[Math.floor(iteration / maxIteration * (chars.length - 1))];
      }
    }
    result += "\n"; // Newline
  }

  console.log(result);
}

drawMandelbrot();
