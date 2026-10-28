"""make_hd_photos／inspect_sources 的合成測試：用程式畫的「照片」走一遍三種分流。

python3 -m unittest discover -s tools/gen-practice-photos
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms

import inspect_sources as ins
import make_hd_photos as hd


def fake_photo(w: int, h: int, seed: int = 0) -> Image.Image:
    """直幅假照片：大塊漸層加一點紋理，縮放後 SSIM 才有意義。"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    base = np.stack([
        128 + 90 * np.sin(xx / w * 3.1 + seed),
        128 + 90 * np.cos(yy / h * 2.3),
        128 + 60 * np.sin((xx + yy) / (w + h) * 5.0),
    ], axis=-1)
    texture = rng.normal(0, 6, (h // 8 + 1, w // 8 + 1, 3)).repeat(8, 0).repeat(8, 1)[:h, :w]
    return Image.fromarray(np.clip(base + texture, 0, 255).astype(np.uint8), 'RGB')


UPSCALER = """
import sys
from PIL import Image
im = Image.open(sys.argv[1])
im.resize((im.size[0] * 2, im.size[1] * 2), Image.LANCZOS).save(sys.argv[2])
"""

WRONG_UPSCALER = """
import sys
from PIL import Image, ImageOps
im = ImageOps.invert(Image.open(sys.argv[1]).convert('RGB'))
im.resize((im.size[0] * 2, im.size[1] * 2), Image.LANCZOS).save(sys.argv[2])
"""


class HdPhotosTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.src, self.current, self.out = root / 'src', root / 'current', root / 'out'
        self.src.mkdir()
        self.current.mkdir()
        self.root = root

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def add(self, n: int, w: int, h: int, icc: bytes | None = None) -> Image.Image:
        """放一張來源 PNG，同時用它做出現有的 1080 高 JPEG。"""
        photo_id = f'practice_girl_{n:03d}'
        im = fake_photo(w, h, seed=n)
        kwargs = {'icc_profile': icc} if icc else {}
        im.save(self.src / f'{photo_id}.png', **kwargs)
        scale = 1080 / max(w, h)
        im.resize((round(w * scale), round(h * scale)), Image.LANCZOS).save(
            self.current / f'{photo_id}.jpg', quality=82)
        return im

    def script(self, name: str, body: str) -> str:
        path = self.root / name
        path.write_text(body)
        return f'{sys.executable} {path} {{in}} {{out}}'

    def run_all(self, count: int, cmd: str | None = None) -> dict:
        return hd.make_all(self.src, self.current, self.out, count, cmd)

    def test_來源夠大就縮到長邊1800_WebP不帶中繼資料(self) -> None:
        srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
        self.add(1, 1500, 2000, icc=srgb)
        report = self.run_all(1)
        row = report['photos']['practice_girl_001']
        self.assertEqual(row['route'], 'downscale')
        with Image.open(self.out / 'practice_girl_001.webp') as out:
            self.assertEqual(out.format, 'WEBP')
            self.assertEqual(out.size, (1350, 1800))
            self.assertNotIn('icc_profile', out.info)
            self.assertNotIn('exif', out.info)
        self.assertEqual(report['exceptions'], [])

    def test_來源不夠大又沒給超解析_用原尺寸並列為例外(self) -> None:
        self.add(1, 900, 1200)
        report = self.run_all(1)
        row = report['photos']['practice_girl_001']
        self.assertEqual(row['route'], 'native')
        self.assertEqual(row['size'], [900, 1200])
        self.assertEqual(report['exceptions'], ['practice_girl_001'])

    def test_超解析結果跟現有照片一致才採用(self) -> None:
        self.add(1, 1200, 1600)
        report = self.run_all(1, self.script('up.py', UPSCALER))
        row = report['photos']['practice_girl_001']
        self.assertEqual(row['route'], 'upscaled')
        self.assertGreaterEqual(row['ssim'], hd.SSIM_MIN)
        self.assertEqual(row['size'], [1350, 1800])

    def test_超解析結果不像原圖_退回原尺寸(self) -> None:
        self.add(1, 1200, 1600)
        report = self.run_all(1, self.script('wrong.py', WRONG_UPSCALER))
        row = report['photos']['practice_girl_001']
        self.assertEqual(row['route'], 'native')
        self.assertLess(row['ssim'], hd.SSIM_MIN)
        self.assertEqual(row['size'], [1200, 1600])

    def test_缺檔列出來_報告與對照圖都寫出(self) -> None:
        self.add(1, 1500, 2000)
        self.add(3, 900, 1200)
        report = self.run_all(3)
        self.assertEqual(report['missing'], ['practice_girl_002'])
        saved = json.loads((self.out / 'report.json').read_text())
        self.assertEqual(saved['missing'], ['practice_girl_002'])
        self.assertEqual(report['compare_pages'], ['compare_01.jpg'])
        self.assertTrue((self.out / 'compare_01.jpg').exists())
        self.assertFalse(report['over_budget'])

    def test_重跑逐位元相同(self) -> None:
        self.add(1, 1500, 2000)
        self.run_all(1)
        first = (self.out / 'practice_girl_001.webp').read_bytes()
        self.run_all(1)
        self.assertEqual((self.out / 'practice_girl_001.webp').read_bytes(), first)

    def test_inspect_只讀檔頭_分出缺檔(self) -> None:
        self.add(1, 1500, 2000)
        self.add(2, 900, 1200)
        result = ins.inspect(self.src, 3)
        self.assertEqual(result['rows'], [('practice_girl_001', 1500, 2000),
                                          ('practice_girl_002', 900, 1200)])
        self.assertEqual(result['missing'], ['practice_girl_003'])


class SsimTest(unittest.TestCase):
    def test_同一張是1_加雜訊變低(self) -> None:
        a = fake_photo(200, 260, seed=7)
        self.assertAlmostEqual(hd.ssim(a, a), 1.0, places=6)
        noisy = np.asarray(a, dtype=np.float64) + np.random.default_rng(1).normal(0, 40, (260, 200, 3))
        b = Image.fromarray(np.clip(noisy, 0, 255).astype(np.uint8), 'RGB')
        self.assertLess(hd.ssim(a, b), 0.6)

    def test_尺寸不同直接報錯(self) -> None:
        with self.assertRaises(ValueError):
            hd.ssim(fake_photo(100, 120), fake_photo(100, 121))

    def test_編碼參數(self) -> None:
        data = hd.encode_webp(fake_photo(60, 80))
        with Image.open(io.BytesIO(data)) as im:
            self.assertEqual(im.format, 'WEBP')


if __name__ == '__main__':
    unittest.main()
