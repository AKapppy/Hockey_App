from __future__ import annotations

import unittest

from hockey_app.ui.components import logo_bank as logo_bank_mod


class LogoAreaScaleTests(unittest.TestCase):
    def test_visible_area_scale_shrinks_dense_logo(self) -> None:
        scale = logo_bank_mod._visible_area_height_scale(
            area_factor=1.4,
        )

        self.assertLess(scale, 1.0)

    def test_visible_area_scale_grows_sparse_logo(self) -> None:
        scale = logo_bank_mod._visible_area_height_scale(
            area_factor=0.55,
        )

        self.assertGreater(scale, 1.0)

    def test_visible_area_scale_is_clamped(self) -> None:
        tiny = logo_bank_mod._visible_area_height_scale(
            area_factor=0.02,
        )
        huge = logo_bank_mod._visible_area_height_scale(
            area_factor=4.0,
        )

        self.assertEqual(tiny, 1.18)
        self.assertEqual(huge, 0.72)


@unittest.skipUnless(logo_bank_mod.PIL_OK, "Pillow is required for logo alpha tests")
class LogoBankTests(unittest.TestCase):
    def test_geometric_area_counts_enclosed_holes(self) -> None:
        img = logo_bank_mod.Image.new("RGBA", (10, 10), (255, 255, 255, 0))  # type: ignore[union-attr]
        for x in range(10):
            img.putpixel((x, 0), (255, 255, 255, 255))
            img.putpixel((x, 9), (255, 255, 255, 255))
        for y in range(10):
            img.putpixel((0, y), (255, 255, 255, 255))
            img.putpixel((9, y), (255, 255, 255, 255))

        area_factor = logo_bank_mod._geometric_area_factor_rgba(img)

        self.assertEqual(area_factor, 1.0)

    def test_crop_transparent_padding_uses_actual_mark_bounds(self) -> None:
        img = logo_bank_mod.Image.new("RGBA", (10, 10), (255, 255, 255, 0))  # type: ignore[union-attr]
        for x in range(3, 7):
            for y in range(2, 8):
                img.putpixel((x, y), (255, 255, 255, 255))

        cropped = logo_bank_mod._crop_transparent_padding_rgba(img)

        self.assertEqual(cropped.size, (4, 6))

    def test_apply_dim_rgba_scales_alpha_channel(self) -> None:
        img = logo_bank_mod.Image.new("RGBA", (1, 1), (255, 255, 255, 200))  # type: ignore[union-attr]

        out = logo_bank_mod._apply_dim_rgba(img, 0.5)

        self.assertEqual(out.getpixel((0, 0))[3], 100)


if __name__ == "__main__":
    unittest.main()
