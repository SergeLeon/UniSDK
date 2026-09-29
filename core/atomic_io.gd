@tool
class_name UniAtomicIO
extends RefCounted

## Атомарная запись файла: пишем во временный, затем переименовываем.
static func write_string(abs_path: String, content: String) -> bool:
	var tmp := abs_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()

	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	return DirAccess.rename_absolute(tmp, abs_path) == OK
