import unittest, os
import ../src/blurhash, imageman/[images, colors]

setCurrentDir getAppDir()

suite "Blurhash":
  let
    image = loadImage[ColorRGBAF] "image.png"
    blur = image.encode

  test "Components":
    check blur.components == (4, 4)

  test "Encoding":
    check blur == "UrQ]$mfQ~qj@ocofWFWB?bj[D%azf6WBj[t7"

  test "Single component encoding":
    check image.encode(1, 1) == "00Q]$m"

  test "Decoding":
    let blurred = decode[ColorRGBU](blur, 400, 400)
    check blurred == loadImage[ColorRGBU] "blurred.png"
