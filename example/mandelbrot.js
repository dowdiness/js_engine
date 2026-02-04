/**
 * マンデルブロ集合 ASCIIアート版
 */
function drawMandelbrot() {
  const width = 70; // 描画幅
  const height = 40; // 描画高さ
  const maxIteration = 50; // 最大計算回数

  // ASCIIアート用の文字（集合の内部ほど文字が濃くなる）
  const chars = " .:-=+*#%@";

  let result = "";

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // 画面座標を複素平面上の座標に変換 (-2.0 < re < 1.0, -1.0 < im < 1.0)
      let c_re = (x - width / 1.5) * 3.0 / width;
      let c_im = (y - height / 2) * 2.0 / height;

      let z_re = 0;
      let z_im = 0;
      let iteration = 0;

      // マンデルブロの繰り返し計算: z = z^2 + c
      while (z_re * z_re + z_im * z_im <= 4 && iteration < maxIteration) {
        let next_re = z_re * z_re - z_im * z_im + c_re;
        let next_im = 2 * z_re * z_im + c_im;
        z_re = next_re;
        z_im = next_im;
        iteration++;
      }

      // 発散までの速度で文字を決める
      if (iteration === maxIteration) {
        result += "@"; // 集合内部
      } else {
        result += chars[Math.floor(iteration / maxIteration * (chars.length - 1))];
      }
    }
    result += "\n"; // 改行
  }

  console.log(result);
}

drawMandelbrot();
