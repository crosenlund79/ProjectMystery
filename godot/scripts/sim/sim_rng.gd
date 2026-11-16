## Deterministic random streams for the town simulation (mirrors mystery/rng.py).
##
## A stream is seeded from SHA-256 of "part|part|...", as derive_seed() does in Python, so the same seed
## and labels give the same stream on every machine. Only integer arithmetic (Godot's PCG32) and exact
## floating-point steps are used: no log, cos or randfn, whose last digit can differ between platforms.
## Exact reproduction of Python's random numbers is not a goal: the streams are equivalent, not equal.
extends RefCounted

## Quantiles of Beta(2.2, 2.2) at k/256, k = 0..256: personality traits are drawn from this distribution in
## Python (random.betavariate(2.2, 2.2)). Interpolating the table gives the same distribution (mean 0.500,
## standard deviation 0.215) with exact arithmetic only. Regenerate with: python3 tools/sim_reference.py --beta-table
const BETA_22 := [
	0.000000, 0.044610, 0.061535, 0.074362, 0.085112, 0.094554, 0.103076, 0.110907, 0.118197, 0.125047,
	0.131531, 0.137704, 0.143610, 0.149283, 0.154751, 0.160035, 0.165154, 0.170126, 0.174962, 0.179675,
	0.184276, 0.188771, 0.193171, 0.197480, 0.201707, 0.205855, 0.209930, 0.213937, 0.217879, 0.221760,
	0.225584, 0.229354, 0.233072, 0.236741, 0.240364, 0.243942, 0.247478, 0.250974, 0.254432, 0.257853,
	0.261239, 0.264591, 0.267910, 0.271199, 0.274458, 0.277688, 0.280891, 0.284067, 0.287218, 0.290344,
	0.293446, 0.296526, 0.299584, 0.302620, 0.305636, 0.308632, 0.311608, 0.314566, 0.317507, 0.320429,
	0.323335, 0.326225, 0.329099, 0.331958, 0.334802, 0.337631, 0.340447, 0.343249, 0.346038, 0.348815,
	0.351579, 0.354332, 0.357073, 0.359802, 0.362521, 0.365229, 0.367928, 0.370616, 0.373295, 0.375964,
	0.378624, 0.381276, 0.383919, 0.386554, 0.389181, 0.391800, 0.394412, 0.397017, 0.399615, 0.402205,
	0.404790, 0.407368, 0.409940, 0.412506, 0.415066, 0.417621, 0.420171, 0.422715, 0.425255, 0.427789,
	0.430320, 0.432846, 0.435367, 0.437885, 0.440399, 0.442909, 0.445416, 0.447919, 0.450420, 0.452917,
	0.455411, 0.457903, 0.460392, 0.462879, 0.465364, 0.467846, 0.470327, 0.472806, 0.475283, 0.477759,
	0.480233, 0.482707, 0.485179, 0.487651, 0.490121, 0.492592, 0.495061, 0.497531, 0.500000, 0.502469,
	0.504939, 0.507408, 0.509879, 0.512349, 0.514821, 0.517293, 0.519767, 0.522241, 0.524717, 0.527194,
	0.529673, 0.532154, 0.534636, 0.537121, 0.539608, 0.542097, 0.544589, 0.547083, 0.549580, 0.552081,
	0.554584, 0.557091, 0.559601, 0.562115, 0.564633, 0.567154, 0.569680, 0.572211, 0.574745, 0.577285,
	0.579829, 0.582379, 0.584934, 0.587494, 0.590060, 0.592632, 0.595210, 0.597795, 0.600385, 0.602983,
	0.605588, 0.608200, 0.610819, 0.613446, 0.616081, 0.618724, 0.621376, 0.624036, 0.626705, 0.629384,
	0.632072, 0.634771, 0.637479, 0.640198, 0.642927, 0.645668, 0.648421, 0.651185, 0.653962, 0.656751,
	0.659553, 0.662369, 0.665198, 0.668042, 0.670901, 0.673775, 0.676665, 0.679571, 0.682493, 0.685434,
	0.688392, 0.691368, 0.694364, 0.697380, 0.700416, 0.703474, 0.706554, 0.709656, 0.712782, 0.715933,
	0.719109, 0.722312, 0.725542, 0.728801, 0.732090, 0.735409, 0.738761, 0.742147, 0.745568, 0.749026,
	0.752522, 0.756058, 0.759636, 0.763259, 0.766928, 0.770646, 0.774416, 0.778240, 0.782121, 0.786063,
	0.790070, 0.794145, 0.798293, 0.802520, 0.806829, 0.811229, 0.815724, 0.820325, 0.825038, 0.829874,
	0.834846, 0.839965, 0.845249, 0.850717, 0.856390, 0.862296, 0.868469, 0.874953, 0.881803, 0.889093,
	0.896924, 0.905446, 0.914888, 0.925638, 0.938465, 0.955390, 1.000000
]

var _rng := RandomNumberGenerator.new()


func _init(parts: Array = []) -> void:
	_rng.seed = derive_seed(parts)


static func derive_seed(parts: Array) -> int:
	var words := PackedStringArray()
	for p in parts:
		words.append(str(p))
	var digest := "|".join(words).sha256_buffer()
	var v := 0
	for i in 7:  # 56 bits: always a positive int
		v = (v << 8) | int(digest[i])
	return v


func random() -> float:
	## Uniform in [0, 1].
	return _rng.randf()


func uniform(a: float, b: float) -> float:
	return a + (b - a) * _rng.randf()


func randint(a: int, b: int) -> int:
	## Inclusive at both ends, like Python's randint.
	return _rng.randi_range(a, b)


func randrange(n: int) -> int:
	return _rng.randi_range(0, n - 1)


func choice(items: Array):
	return items[randrange(items.size())]


func shuffle(items: Array) -> void:
	## Fisher-Yates in place. Never Array.shuffle(): it uses the global generator, not this stream.
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func sample(items: Array, k: int) -> Array:
	## k distinct items in random order, like Python's random.sample.
	var pool := items.duplicate()
	var out := []
	for i in mini(k, pool.size()):
		var j := _rng.randi_range(i, pool.size() - 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		out.append(pool[i])
	return out


func beta22() -> float:
	var u := _rng.randf() * 256.0
	var i := mini(255, int(u))
	var f := u - float(i)
	return float(BETA_22[i]) + (float(BETA_22[i + 1]) - float(BETA_22[i])) * f
