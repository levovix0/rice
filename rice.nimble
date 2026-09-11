version       = "0.1.6"
author        = "levovix0"
description   = "2D GPU rendering library for graphical interfaces"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.4"

requires "chroma"  # for colors
requires "vmath"   # for vectors
requires "opengl"  # for opengl functions
requires "https://github.com/levovix0/shady"  # for writing shaders in nim
requires "https://github.com/levovix0/pixie_reorganized"   # for fonts and paths

feature "rice_examples":
  requires "siwin"

