class_name NumberFormat
extends RefCounted
## Display helpers for numbers shown in the interface.


## 1234567 -> "1,234,567".
static func with_commas(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return "-" + result if value < 0 else result
