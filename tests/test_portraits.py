from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from tools.generate_portraits import png_alpha, validate_portraits


def png(width: int = 24,height: int = 32,empty: bool = False) -> bytes:
    def chunk(kind: bytes,data: bytes) -> bytes:
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
    rows = bytearray()
    previous = bytes(width*4)
    for y in range(height):
        raw = bytes(value for x in range(width) for value in
                    (x*9%256,y*11%256,71,137 if not empty and 4<=x<width-4 and 5<=y<height-5 else 0))
        mode = y%5
        filtered = bytearray()
        for index,value in enumerate(raw):
            left = raw[index-4] if index>=4 else 0
            above = previous[index]
            corner = previous[index-4] if index>=4 else 0
            if mode==0: predictor=0
            elif mode==1: predictor=left
            elif mode==2: predictor=above
            elif mode==3: predictor=(left+above)//2
            else:
                distances=[abs(left+above-corner-value) for value in (left,above,corner)]
                predictor=(left,above,corner)[distances.index(min(distances))]
            filtered.append((value-predictor)&255)
        rows.extend(bytes([mode])+filtered)
        previous=raw
    return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(rows))+chunk(b"IEND",b"")


class PortraitValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="FantasySiegePortraitTests_")
        self.root = Path(self.temp.name)
        (self.root/"resources").mkdir()
        self.directory=self.root/"assets"/"portraits"
        self.directory.mkdir(parents=True)
        (self.root/"project.godot").write_text('[application]\nconfig/version="0.1.3.0"\n',encoding="utf-8")
        units={"hero_"+str(index):{"visual_id":"d69_"+str(index),"playable":True} for index in range(12)}
        (self.root/"resources"/"units.json").write_text(json.dumps(units),encoding="utf-8")
        visual_source=b'{"test_visual_recipe":"native idle"}'
        (self.root/"resources"/"visuals.json").write_bytes(visual_source)
        self.manifest={"program_version":"0.1.3.0","passed":True,"visuals_sha256":hashlib.sha256(visual_source).hexdigest(),"rendering_adapter":"test fixture","entries":[]}
        for unit_id,unit in units.items():
            image=png()
            (self.directory/(unit_id+".png")).write_bytes(image)
            self.manifest["entries"].append({"unit_id":unit_id,"visual_id":unit["visual_id"],"png":unit_id+".png","sha256":hashlib.sha256(image).hexdigest(),"width":24,"height":32,"native":True,"nonempty":True})
        self.write_manifest()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self) -> None:
        (self.directory/"manifest.json").write_text(json.dumps(self.manifest),encoding="utf-8")

    def test_rgba_png_filters_preserve_alpha_bounds(self) -> None:
        info=png_alpha(self.directory/"hero_0.png")
        self.assertEqual(info["alpha_bounds"],[4,5,19,26])
        self.assertEqual(info["nonzero_alpha_pixels"],16*22)
        self.assertEqual(info["transparent_pixels"],24*32-16*22)
        self.assertTrue(validate_portraits(self.root)["passed"])

    def test_wrong_identity_and_placeholder_are_rejected(self) -> None:
        self.manifest["entries"][0]["visual_id"]="d69_other"
        self.manifest["entries"][1]["native"]=False
        self.write_manifest()
        result=validate_portraits(self.root)
        self.assertFalse(result["passed"])
        self.assertTrue(any("visual_id mismatch" in error for error in result["failures"]))
        self.assertTrue(any("placeholder" in error for error in result["failures"]))

    def test_stale_recipe_and_png_tamper_are_rejected(self) -> None:
        (self.root/"resources"/"visuals.json").write_text('{"recipe":"changed"}',encoding="utf-8")
        (self.directory/"hero_0.png").write_bytes(png(empty=True))
        result=validate_portraits(self.root)
        self.assertFalse(result["passed"])
        self.assertTrue(any("source hash mismatch" in error for error in result["failures"]))
        self.assertTrue(any("SHA256 mismatch" in error for error in result["failures"]))

    def test_empty_alpha_is_rejected_even_with_matching_hash(self) -> None:
        image=png(empty=True)
        (self.directory/"hero_0.png").write_bytes(image)
        self.manifest["entries"][0]["sha256"]=hashlib.sha256(image).hexdigest()
        self.write_manifest()
        self.assertFalse(validate_portraits(self.root)["passed"])

    def test_old_manifest_does_not_satisfy_fresh_generation(self) -> None:
        newer=(self.directory/"manifest.json").stat().st_mtime_ns+5_000_000
        self.assertFalse(validate_portraits(self.root,newer)["passed"])


if __name__=="__main__":
    unittest.main()
