version       = "0.1.8"
author        = "levovix0"
description   = "2D GPU rendering library for graphical interfaces"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.4"

requires "chroma"  # for colors
requires "vmath"   # for vectors
requires "opengl"  # for opengl functions
requires "https://github.com/levovix0/pixie_reorganized"   # for fonts and paths

feature "shady":
  # for the rice/shaders module (the `makeShader` macro);
  # the rest of rice doesn't depend on shady,
  # import rice/shaders if you need it, it is not re-exported in root rice
  requires "https://github.com/levovix0/shady"

feature "rice_examples":
  requires "siwin"

