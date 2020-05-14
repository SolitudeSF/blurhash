import math
import imageman/[images, colors]

const base83chars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B',
  'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q',
  'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
  'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u',
  'v', 'w', 'x', 'y', 'z', '#', '$', '%', '*', '+', ',', '-', '.', ':', ';',
  '=', '?', '@', '[', ']', '^', '_', '{', '|', '}', '~']

template matchingRGB[T: Color](t: typedesc[T]): typedesc =
  when T is ColorHSL:
    ColorRGBF
  elif T is (ColorHSLuv | ColorHPLuv):
    ColorRGBF64
  else:
    T

func intPow(a, b: int): int =
  result = 1
  for _ in 1..b:
    result *= a

func signPow(a, b: float): float =
  if a < 0:
    pow(abs(a), b) * -1
  else:
    pow(a, b)

func encode83(n, l: int): string =
  result = newString(l)
  for i in 1..l:
    result[i - 1] = base83chars[(n div intPow(83, l - i)) mod 83]

func decode83(s: string): int =
  for c in s:
    result = result * 83 + base83chars.find(c)

func toXYZ(n: uint8): float32 =
  result = n.float32 / 255.0
  if result <= 0.04045:
    result = result / 12.92
  else:
    result = pow((result + 0.055) / 1.055, 2.4)

func toXYZ(n: float32): float32 =
  if n <= 0.04045:
     n / 12.92
  else:
    pow((n + 0.055) / 1.055, 2.4)

func toFloatSrgb[T: float32 | float64](n: T): T =
  let v = n.clamp(0, 1)
  if v <= 0.0031308:
    (v * 12.92 * 255.0 + 0.5) / 255.0
  else:
    ((pow(v, 1.0 / 2.4) * 1.055  - 0.055) * 255.0 + 0.5) / 255.0

func toUintSrgb(n: float32): uint8 =
  let v = n.clamp(0, 1)
  if v <= 0.0031308:
    uint8(v * 12.92 * 255.0 + 0.5)
  else:
    uint8((pow(v, 1.0 / 2.4) * 1.055  - 0.055) * 255.0 + 0.5)

func components*(s: string): tuple[x, y: int] =
  ## Returns x, y components of given blurhash
  let size = base83chars.find(s[0])
  result = ((size mod 9) + 1, (size div 9) + 1)

  if s.len != 4 + 2 * result.x * result.y:
    raise newException(ValueError, "Invalid Blurhash string.")

func encode*[T: Color](img: Image[T], componentsX = 4, componentsY = 4): string =
  ## Calculates Blurhash for an image using the given x and y component counts.
  ##
  ## Component counts must be between 1 and 9 inclusive.
  assert componentsX <= 9 and componentsX >= 1 and
         componentsY <= 9 and componentsY >= 1

  let len = img.data.len.float
  var
    comps = newSeq[array[3, float]](componentsX * componentsY)
    maxComponent = 0.0

  for j in 0..<componentsY:
    for i in 0..<componentsX:
      let normFactor = if (j == 0 and i == 0): 1.0 else: 2.0
      var comp: array[3, float]

      for y in 0..<img.height:
        let yw = y * img.width
        for x in 0..<img.width:
          let basis = normFactor * cos(PI * i.float * x.float / img.width.float) *
                                   cos(PI * j.float * y.float / img.height.float)
          comp[0] += basis * img[x + yw][0].toXYZ
          comp[1] += basis * img[x + yw][1].toXYZ
          comp[2] += basis * img[x + yw][2].toXYZ

      comp[0] /= len
      comp[1] /= len
      comp[2] /= len
      comps[j * componentsX + i] = comp

      if not (i == 0 and j == 0):
        maxComponent = max [maxComponent, abs comp[0], abs comp[1], abs comp[2]]

  let
    dcValue = (comps[0][0].toUintSrgb.int shl 16) +
              (comps[0][1].toUintSrgb.int shl 8) + comps[0][2].toUintSrgb.int
    quantMaxValue = int max(0, min(82, floor(maxComponent * 166 - 0.5)))

  var normMaxValue: float

  result &= encode83(componentsX - 1 + (componentsY - 1) * 9, 1)

  if comps.len > 1:
    normMaxValue = float(quantMaxValue + 1) / 166.0
    result &= quantMaxValue.encode83(1)
  else:
    normMaxValue = 1.0
    result &= 0.encode83(1)

  result &= dcValue.encode83(4)

  for i in 1..comps.high:
    result &= (int(max(0, min(18, floor(signPow(comps[i][0] / normMaxValue, 0.5) * 9 + 9.5)))) * 19 * 19 +
               int(max(0, min(18, floor(signPow(comps[i][1] / normMaxValue, 0.5) * 9 + 9.5)))) * 19 +
               int(max(0, min(18, floor(signPow(comps[i][2] / normMaxValue, 0.5) * 9 + 9.5))))).
               encode83(2)

func decode*[T: Color](s: string, width, height: int, punch = 1.0): Image[T] =
  ## Decodes given blurhash to an RGB image with specified dimensions
  ##
  ## Punch parameter can be used to increase/decrease contrast of the resulting image
  let
    (sizeX, sizeY) = s.components
    quantMaxValue = base83chars.find s[1]
    maxValue = float(quantMaxValue + 1) / 166.0 * punch

  let dcValue = s[2..5].decode83
  var colors = newSeq[array[3, float32]](sizeX * sizeY)

  colors[0] = [(dcValue shr 16).uint8.toXYZ,
               ((dcValue shr 8) and 255).uint8.toXYZ,
               (dcValue and 255).uint8.toXYZ]

  for i in 1..colors.high:
    let acValue = s[4 + i * 2..5 + i * 2].decode83
    colors[i][0] = signPow((float(acValue div (19 * 19)) - 9) / 9, 2) * maxValue
    colors[i][1] = signPow((float((acValue div 19) mod 19) - 9) / 9, 2) * maxValue
    colors[i][2] = signPow((float(acValue mod 19) - 9) / 9, 2) * maxValue

  var r = initImage[T.matchingRGB](width, height)

  for y in 0..<height:
    let yw = y * width
    for x in 0..<width:
      var pixel: array[3, float]

      for j in 0..<sizeY:
        for i in 0..<sizeX:
          let
            basis = cos(PI * i.float * x.float / width.float) *
                    cos(PI * j.float * y.float / height.float)
            color = colors[i + j * sizeX]
          pixel[0] += color[0] * basis
          pixel[1] += color[1] * basis
          pixel[2] += color[2] * basis
      let xyw = x + yw
      when r.colorType is (ColorRGBFAny | ColorRGBF64Any):
        r[xyw][0] = pixel[0].toFloatSrgb
        r[xyw][1] = pixel[1].toFloatSrgb
        r[xyw][2] = pixel[2].toFloatSrgb
      else:
        r[xyw][0] = pixel[0].toUintSrgb
        r[xyw][1] = pixel[1].toUintSrgb
        r[xyw][2] = pixel[2].toUintSrgb
      when T is ColorA:
        r[xyw][3] = T.maxComponentValue

  when r.colorType is T:
    return r
  else:
    return r.to(T)
