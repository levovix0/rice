version       = "0.1.3"
author        = "levovix0"
description   = "2D GPU rendering library for graphical interfaces"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.4"

requires "chroma"  # for colors
requires "vmath"   # for vectors
requires "opengl"  # for opengl functions
requires "shady"   # for writing shaders in nim
# requires "shady == 0.1.4"  # breaks atlas somehow
requires "pixie"   # for fonts and paths

