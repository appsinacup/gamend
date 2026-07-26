#
# BSD 3-Clause License
#
# Copyright (c) 2018 - 2026, Oleg Malyavkin
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# DEBUG_TAB redefine this "  " if you need, example: const DEBUG_TAB = "\t"

const PROTO_VERSION = 3

const DEBUG_TAB : String = "  "

enum PB_ERR {
	NO_ERRORS = 0,
	VARINT_NOT_FOUND = -1,
	REPEATED_COUNT_NOT_FOUND = -2,
	REPEATED_COUNT_MISMATCH = -3,
	LENGTHDEL_SIZE_NOT_FOUND = -4,
	LENGTHDEL_SIZE_MISMATCH = -5,
	PACKAGE_SIZE_MISMATCH = -6,
	UNDEFINED_STATE = -7,
	PARSE_INCOMPLETE = -8,
	REQUIRED_FIELDS = -9
}

enum PB_DATA_TYPE {
	INT32 = 0,
	SINT32 = 1,
	UINT32 = 2,
	INT64 = 3,
	SINT64 = 4,
	UINT64 = 5,
	BOOL = 6,
	ENUM = 7,
	FIXED32 = 8,
	SFIXED32 = 9,
	FLOAT = 10,
	FIXED64 = 11,
	SFIXED64 = 12,
	DOUBLE = 13,
	STRING = 14,
	BYTES = 15,
	MESSAGE = 16,
	MAP = 17
}

const DEFAULT_VALUES_2 = {
	PB_DATA_TYPE.INT32: null,
	PB_DATA_TYPE.SINT32: null,
	PB_DATA_TYPE.UINT32: null,
	PB_DATA_TYPE.INT64: null,
	PB_DATA_TYPE.SINT64: null,
	PB_DATA_TYPE.UINT64: null,
	PB_DATA_TYPE.BOOL: null,
	PB_DATA_TYPE.ENUM: null,
	PB_DATA_TYPE.FIXED32: null,
	PB_DATA_TYPE.SFIXED32: null,
	PB_DATA_TYPE.FLOAT: null,
	PB_DATA_TYPE.FIXED64: null,
	PB_DATA_TYPE.SFIXED64: null,
	PB_DATA_TYPE.DOUBLE: null,
	PB_DATA_TYPE.STRING: null,
	PB_DATA_TYPE.BYTES: null,
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: null
}

const DEFAULT_VALUES_3 = {
	PB_DATA_TYPE.INT32: 0,
	PB_DATA_TYPE.SINT32: 0,
	PB_DATA_TYPE.UINT32: 0,
	PB_DATA_TYPE.INT64: 0,
	PB_DATA_TYPE.SINT64: 0,
	PB_DATA_TYPE.UINT64: 0,
	PB_DATA_TYPE.BOOL: false,
	PB_DATA_TYPE.ENUM: 0,
	PB_DATA_TYPE.FIXED32: 0,
	PB_DATA_TYPE.SFIXED32: 0,
	PB_DATA_TYPE.FLOAT: 0.0,
	PB_DATA_TYPE.FIXED64: 0,
	PB_DATA_TYPE.SFIXED64: 0,
	PB_DATA_TYPE.DOUBLE: 0.0,
	PB_DATA_TYPE.STRING: "",
	PB_DATA_TYPE.BYTES: [],
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: []
}

enum PB_TYPE {
	VARINT = 0,
	FIX64 = 1,
	LENGTHDEL = 2,
	STARTGROUP = 3,
	ENDGROUP = 4,
	FIX32 = 5,
	UNDEFINED = 8
}

enum PB_RULE {
	OPTIONAL = 0,
	REQUIRED = 1,
	REPEATED = 2,
	RESERVED = 3
}

enum PB_SERVICE_STATE {
	FILLED = 0,
	UNFILLED = 1
}

class PBField:
	extends RefCounted
	func _init(a_name : String, a_type : int, a_rule : int, a_tag : int, packed : bool, a_value = null):
		name = a_name
		type = a_type
		rule = a_rule
		tag = a_tag
		option_packed = packed
		value = a_value
		
	var name : String
	var type : int
	var rule : int
	var tag : int
	var option_packed : bool
	var value
	var is_map_field : bool = false
	var option_default : bool = false

class PBTypeTag:
	extends RefCounted
	var ok : bool = false
	var type : int
	var tag : int
	var offset : int

class PBServiceField:
	extends RefCounted
	var field : PBField
	var func_ref = null
	var state : int = PB_SERVICE_STATE.UNFILLED

class PBPacker:
	static func convert_signed(n : int) -> int:
		if n < -2147483648:
			return (n << 1) ^ (n >> 63)
		else:
			return (n << 1) ^ (n >> 31)

	static func deconvert_signed(n : int) -> int:
		if n & 0x01:
			return ~(n >> 1)
		else:
			return (n >> 1)

	static func pack_varint(value) -> PackedByteArray:
		var varint : PackedByteArray = PackedByteArray()
		if typeof(value) == TYPE_BOOL:
			if value:
				value = 1
			else:
				value = 0
		for _i in range(9):
			var b = value & 0x7F
			value >>= 7
			if value:
				varint.append(b | 0x80)
			else:
				varint.append(b)
				break
		if varint.size() == 9 && (varint[8] & 0x80 != 0):
			varint.append(0x01)
		return varint

	static func pack_bytes(value, count : int, data_type : int) -> PackedByteArray:
		var bytes : PackedByteArray = PackedByteArray()
		if data_type == PB_DATA_TYPE.FLOAT:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_float(value)
			bytes = spb.get_data_array()
		elif data_type == PB_DATA_TYPE.DOUBLE:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_double(value)
			bytes = spb.get_data_array()
		else:
			for _i in range(count):
				bytes.append(value & 0xFF)
				value >>= 8
		return bytes

	static func unpack_bytes(bytes : PackedByteArray, index : int, count : int, data_type : int):
		if data_type == PB_DATA_TYPE.FLOAT:
			return bytes.decode_float(index)
		elif data_type == PB_DATA_TYPE.DOUBLE:
			return bytes.decode_double(index)
		elif data_type == PB_DATA_TYPE.FIXED32:
			return bytes.decode_u32(index)
		elif data_type == PB_DATA_TYPE.SFIXED32:
			return bytes.decode_s32(index)
		elif data_type == PB_DATA_TYPE.FIXED64:
			return bytes.decode_u64(index)
		elif data_type == PB_DATA_TYPE.SFIXED64:
			return bytes.decode_s64(index)
		else:
			var value : int = 0
			for i in range(count):
				value |= bytes[index + i] << (8 * i)
			return value

	static func unpack_varint(varint_bytes) -> int:
		var value : int = 0
		var i: int = varint_bytes.size() - 1
		while i > -1:
			value = (value << 7) | (varint_bytes[i] & 0x7F)
			i -= 1
		return value

	static func pack_type_tag(type : int, tag : int) -> PackedByteArray:
		return pack_varint((tag << 3) | type)

	static func isolate_varint(bytes : PackedByteArray, index : int) -> PackedByteArray:
		var i: int = index
		while i <= index + 10 && i < bytes.size(): # Protobuf varint max size is 10 bytes
			if !(bytes[i] & 0x80):
				return bytes.slice(index, i + 1)
			i += 1
		return [] # Unreachable

	static func unpack_type_tag(bytes : PackedByteArray, index : int) -> PBTypeTag:
		var varint_bytes : PackedByteArray = isolate_varint(bytes, index)
		var result : PBTypeTag = PBTypeTag.new()
		if varint_bytes.size() != 0:
			result.ok = true
			result.offset = varint_bytes.size()
			var unpacked : int = unpack_varint(varint_bytes)
			result.type = unpacked & 0x07
			result.tag = unpacked >> 3
		return result

	static func pack_length_delimeted(type : int, tag : int, bytes : PackedByteArray) -> PackedByteArray:
		var result : PackedByteArray = pack_type_tag(type, tag)
		result.append_array(pack_varint(bytes.size()))
		result.append_array(bytes)
		return result

	static func pb_type_from_data_type(data_type : int) -> int:
		if data_type == PB_DATA_TYPE.INT32 || data_type == PB_DATA_TYPE.SINT32 || data_type == PB_DATA_TYPE.UINT32 || data_type == PB_DATA_TYPE.INT64 || data_type == PB_DATA_TYPE.SINT64 || data_type == PB_DATA_TYPE.UINT64 || data_type == PB_DATA_TYPE.BOOL || data_type == PB_DATA_TYPE.ENUM:
			return PB_TYPE.VARINT
		elif data_type == PB_DATA_TYPE.FIXED32 || data_type == PB_DATA_TYPE.SFIXED32 || data_type == PB_DATA_TYPE.FLOAT:
			return PB_TYPE.FIX32
		elif data_type == PB_DATA_TYPE.FIXED64 || data_type == PB_DATA_TYPE.SFIXED64 || data_type == PB_DATA_TYPE.DOUBLE:
			return PB_TYPE.FIX64
		elif data_type == PB_DATA_TYPE.STRING || data_type == PB_DATA_TYPE.BYTES || data_type == PB_DATA_TYPE.MESSAGE || data_type == PB_DATA_TYPE.MAP:
			return PB_TYPE.LENGTHDEL
		else:
			return PB_TYPE.UNDEFINED

	static func pack_field(field : PBField) -> PackedByteArray:
		var type : int = pb_type_from_data_type(field.type)
		var type_copy : int = type
		if field.rule == PB_RULE.REPEATED && field.option_packed:
			type = PB_TYPE.LENGTHDEL
		var head : PackedByteArray = pack_type_tag(type, field.tag)
		var data : PackedByteArray = PackedByteArray()
		if type == PB_TYPE.VARINT:
			var value
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						value = convert_signed(v)
					else:
						value = v
					data.append_array(pack_varint(value))
				return data
			else:
				if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
					value = convert_signed(field.value)
				else:
					value = field.value
				data = pack_varint(value)
		elif type == PB_TYPE.FIX32:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 4, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 4, field.type))
		elif type == PB_TYPE.FIX64:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 8, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 8, field.type))
		elif type == PB_TYPE.LENGTHDEL:
			if field.rule == PB_RULE.REPEATED:
				if type_copy == PB_TYPE.VARINT:
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						var signed_value : int
						for v in field.value:
							signed_value = convert_signed(v)
							data.append_array(pack_varint(signed_value))
					else:
						for v in field.value:
							data.append_array(pack_varint(v))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX32:
					for v in field.value:
						data.append_array(pack_bytes(v, 4, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX64:
					for v in field.value:
						data.append_array(pack_bytes(v, 8, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif field.type == PB_DATA_TYPE.STRING:
					for v in field.value:
						var obj = v.to_utf8_buffer()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
				elif field.type == PB_DATA_TYPE.BYTES:
					for v in field.value:
						data.append_array(pack_length_delimeted(type, field.tag, v))
					return data
				elif typeof(field.value[0]) == TYPE_OBJECT:
					for v in field.value:
						var obj : PackedByteArray = v.to_bytes()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
			else:
				if field.type == PB_DATA_TYPE.STRING:
					var str_bytes : PackedByteArray = field.value.to_utf8_buffer()
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && str_bytes.size() > 0):
						data.append_array(str_bytes)
						return pack_length_delimeted(type, field.tag, data)
				if field.type == PB_DATA_TYPE.BYTES:
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && field.value.size() > 0):
						data.append_array(field.value)
						return pack_length_delimeted(type, field.tag, data)
				elif typeof(field.value) == TYPE_OBJECT:
					var obj : PackedByteArray = field.value.to_bytes()
					if obj.size() > 0:
						data.append_array(obj)
					return pack_length_delimeted(type, field.tag, data)
				else:
					pass
		if data.size() > 0:
			head.append_array(data)
			return head
		else:
			return data

	static func skip_unknown_field(bytes : PackedByteArray, offset : int, type : int) -> int:
		if type == PB_TYPE.VARINT:
			return offset + isolate_varint(bytes, offset).size()
		if type == PB_TYPE.FIX64:
			return offset + 8
		if type == PB_TYPE.LENGTHDEL:
			var length_bytes : PackedByteArray = isolate_varint(bytes, offset)
			var length : int = unpack_varint(length_bytes)
			return offset + length_bytes.size() + length
		if type == PB_TYPE.FIX32:
			return offset + 4
		return PB_ERR.UNDEFINED_STATE

	static func unpack_field(bytes : PackedByteArray, offset : int, field : PBField, type : int, message_func_ref) -> int:
		if field.rule == PB_RULE.REPEATED && type != PB_TYPE.LENGTHDEL && field.option_packed:
			var count = isolate_varint(bytes, offset)
			if count.size() > 0:
				offset += count.size()
				count = unpack_varint(count)
				if type == PB_TYPE.VARINT:
					var val
					var counter = offset + count
					while offset < counter:
						val = isolate_varint(bytes, offset)
						if val.size() > 0:
							offset += val.size()
							val = unpack_varint(val)
							if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
								val = deconvert_signed(val)
							elif field.type == PB_DATA_TYPE.BOOL:
								if val:
									val = true
								else:
									val = false
							field.value.append(val)
						else:
							return PB_ERR.REPEATED_COUNT_MISMATCH
					return offset
				elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
					var type_size
					if type == PB_TYPE.FIX32:
						type_size = 4
					else:
						type_size = 8
					var val
					var counter = offset + count
					while offset < counter:
						if (offset + type_size) > bytes.size():
							return PB_ERR.REPEATED_COUNT_MISMATCH
						val = unpack_bytes(bytes, offset, type_size, field.type)
						offset += type_size
						field.value.append(val)
					return offset
			else:
				return PB_ERR.REPEATED_COUNT_NOT_FOUND
		else:
			if type == PB_TYPE.VARINT:
				var val = isolate_varint(bytes, offset)
				if val.size() > 0:
					offset += val.size()
					val = unpack_varint(val)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						val = deconvert_signed(val)
					elif field.type == PB_DATA_TYPE.BOOL:
						if val:
							val = true
						else:
							val = false
					if field.rule == PB_RULE.REPEATED:
						field.value.append(val)
					else:
						field.value = val
				else:
					return PB_ERR.VARINT_NOT_FOUND
				return offset
			elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
				var type_size
				if type == PB_TYPE.FIX32:
					type_size = 4
				else:
					type_size = 8
				var val
				if (offset + type_size) > bytes.size():
					return PB_ERR.REPEATED_COUNT_MISMATCH
				val = unpack_bytes(bytes, offset, type_size, field.type)
				offset += type_size
				if field.rule == PB_RULE.REPEATED:
					field.value.append(val)
				else:
					field.value = val
				return offset
			elif type == PB_TYPE.LENGTHDEL:
				var inner_size = isolate_varint(bytes, offset)
				if inner_size.size() > 0:
					offset += inner_size.size()
					inner_size = unpack_varint(inner_size)
					if inner_size >= 0:
						if inner_size + offset > bytes.size():
							return PB_ERR.LENGTHDEL_SIZE_MISMATCH
						if message_func_ref != null:
							var message = message_func_ref.call()
							if inner_size > 0:
								var sub_offset = message.from_bytes(bytes, offset, inner_size + offset)
								if sub_offset > 0:
									if sub_offset - offset >= inner_size:
										offset = sub_offset
										return offset
									else:
										return PB_ERR.LENGTHDEL_SIZE_MISMATCH
								return sub_offset
							else:
								return offset
						elif field.type == PB_DATA_TYPE.STRING:
							var str_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(str_bytes.get_string_from_utf8())
							else:
								field.value = str_bytes.get_string_from_utf8()
							return offset + inner_size
						elif field.type == PB_DATA_TYPE.BYTES:
							var val_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(val_bytes)
							else:
								field.value = val_bytes
							return offset + inner_size
					else:
						return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
				else:
					return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
		return PB_ERR.UNDEFINED_STATE

	static func unpack_message(data, bytes : PackedByteArray, offset : int, limit : int) -> int:
		while true:
			var tt : PBTypeTag = unpack_type_tag(bytes, offset)
			if tt.ok:
				offset += tt.offset
				if data.has(tt.tag):
					var service : PBServiceField = data[tt.tag]
					var type : int = pb_type_from_data_type(service.field.type)
					if type == tt.type || (tt.type == PB_TYPE.LENGTHDEL && service.field.rule == PB_RULE.REPEATED && service.field.option_packed):
						var res : int = unpack_field(bytes, offset, service.field, type, service.func_ref)
						if res > 0:
							service.state = PB_SERVICE_STATE.FILLED
							offset = res
							if offset == limit:
								return offset
							elif offset > limit:
								return PB_ERR.PACKAGE_SIZE_MISMATCH
						elif res < 0:
							return res
						else:
							break
				else:
					var res : int = skip_unknown_field(bytes, offset, tt.type)
					if res > 0:
						offset = res
						if offset == limit:
							return offset
						elif offset > limit:
							return PB_ERR.PACKAGE_SIZE_MISMATCH
					elif res < 0:
						return res
					else:
						break							
			else:
				return offset
		return PB_ERR.UNDEFINED_STATE

	static func pack_message(data) -> PackedByteArray:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : PackedByteArray = PackedByteArray()
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result.append_array(pack_field(data[i].field))
			elif data[i].field.rule == PB_RULE.REQUIRED:
				print("Error: required field is not filled: Tag:", data[i].field.tag)
				return PackedByteArray()
		return result

	static func check_required(data) -> bool:
		var keys : Array = data.keys()
		for i in keys:
			if data[i].field.rule == PB_RULE.REQUIRED && data[i].state == PB_SERVICE_STATE.UNFILLED:
				return false
		return true

	static func construct_map(key_values):
		var result = {}
		for kv in key_values:
			result[kv.get_key()] = kv.get_value()
		return result
	
	static func tabulate(text : String, nesting : int) -> String:
		var tab : String = ""
		for _i in range(nesting):
			tab += DEBUG_TAB
		return tab + text
	
	static func value_to_string(value, field : PBField, nesting : int) -> String:
		var result : String = ""
		var text : String
		if field.type == PB_DATA_TYPE.MESSAGE:
			result += "{"
			nesting += 1
			text = message_to_string(value.data, nesting)
			if text != "":
				result += "\n" + text
				nesting -= 1
				result += tabulate("}", nesting)
			else:
				nesting -= 1
				result += "}"
		elif field.type == PB_DATA_TYPE.BYTES:
			result += "<"
			for i in range(value.size()):
				result += str(value[i])
				if i != (value.size() - 1):
					result += ", "
			result += ">"
		elif field.type == PB_DATA_TYPE.STRING:
			result += "\"" + value + "\""
		elif field.type == PB_DATA_TYPE.ENUM:
			result += "ENUM::" + str(value)
		else:
			result += str(value)
		return result
	
	static func field_to_string(field : PBField, nesting : int) -> String:
		var result : String = tabulate(field.name + ": ", nesting)
		if field.type == PB_DATA_TYPE.MAP:
			if field.value.size() > 0:
				result += "(\n"
				nesting += 1
				for i in range(field.value.size()):
					var local_key_value = field.value[i].data[1].field
					result += tabulate(value_to_string(local_key_value.value, local_key_value, nesting), nesting) + ": "
					local_key_value = field.value[i].data[2].field
					result += value_to_string(local_key_value.value, local_key_value, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate(")", nesting)
			else:
				result += "()"
		elif field.rule == PB_RULE.REPEATED:
			if field.value.size() > 0:
				result += "[\n"
				nesting += 1
				for i in range(field.value.size()):
					result += tabulate(str(i) + ": ", nesting)
					result += value_to_string(field.value[i], field, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate("]", nesting)
			else:
				result += "[]"
		else:
			result += value_to_string(field.value, field, nesting)
		result += ";\n"
		return result
		
	static func message_to_string(data, nesting : int = 0) -> String:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : String = ""
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result += field_to_string(data[i].field, nesting)
			elif data[i].field.rule == PB_RULE.REQUIRED:
				result += data[i].field.name + ": " + "error"
		return result



############### USER DATA BEGIN ################


class LinkedProviders:
	extends RefCounted
	func _init():
		var service
		
		__google = PBField.new("google", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __google
		data[__google.tag] = service
		
		__facebook = PBField.new("facebook", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __facebook
		data[__facebook.tag] = service
		
		__discord = PBField.new("discord", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __discord
		data[__discord.tag] = service
		
		__apple = PBField.new("apple", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __apple
		data[__apple.tag] = service
		
		__steam = PBField.new("steam", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __steam
		data[__steam.tag] = service
		
		__device = PBField.new("device", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __device
		data[__device.tag] = service
		
	var data = {}
	
	var __google: PBField
	func has_google() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_google() -> bool:
		return __google.value
	func clear_google() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__google.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_google(value : bool) -> void:
		__google.value = value
	
	var __facebook: PBField
	func has_facebook() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_facebook() -> bool:
		return __facebook.value
	func clear_facebook() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__facebook.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_facebook(value : bool) -> void:
		__facebook.value = value
	
	var __discord: PBField
	func has_discord() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_discord() -> bool:
		return __discord.value
	func clear_discord() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__discord.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_discord(value : bool) -> void:
		__discord.value = value
	
	var __apple: PBField
	func has_apple() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_apple() -> bool:
		return __apple.value
	func clear_apple() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__apple.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_apple(value : bool) -> void:
		__apple.value = value
	
	var __steam: PBField
	func has_steam() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_steam() -> bool:
		return __steam.value
	func clear_steam() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__steam.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_steam(value : bool) -> void:
		__steam.value = value
	
	var __device: PBField
	func has_device() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_device() -> bool:
		return __device.value
	func clear_device() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__device.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_device(value : bool) -> void:
		__device.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class User:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__email = PBField.new("email", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __email
		data[__email.tag] = service
		
		__profile_url = PBField.new("profile_url", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __profile_url
		data[__profile_url.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__display_name = PBField.new("display_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __display_name
		data[__display_name.tag] = service
		
		__lobby_id = PBField.new("lobby_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __lobby_id
		data[__lobby_id.tag] = service
		
		__party_id = PBField.new("party_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __party_id
		data[__party_id.tag] = service
		
		__is_online = PBField.new("is_online", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_online
		data[__is_online.tag] = service
		
		__last_seen_at_ms = PBField.new("last_seen_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __last_seen_at_ms
		data[__last_seen_at_ms.tag] = service
		
		__linked_providers = PBField.new("linked_providers", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __linked_providers
		service.func_ref = Callable(self, "new_linked_providers")
		data[__linked_providers.tag] = service
		
		__has_password = PBField.new("has_password", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __has_password
		data[__has_password.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 12, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
		__username = PBField.new("username", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 13, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __username
		data[__username.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __email: PBField
	func has_email() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_email() -> String:
		return __email.value
	func clear_email() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__email.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_email(value : String) -> void:
		__email.value = value
	
	var __profile_url: PBField
	func has_profile_url() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_profile_url() -> String:
		return __profile_url.value
	func clear_profile_url() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__profile_url.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_profile_url(value : String) -> void:
		__profile_url.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __display_name: PBField
	func has_display_name() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_display_name() -> String:
		return __display_name.value
	func clear_display_name() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__display_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_display_name(value : String) -> void:
		__display_name.value = value
	
	var __lobby_id: PBField
	func has_lobby_id() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_lobby_id() -> String:
		return __lobby_id.value
	func clear_lobby_id() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__lobby_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_lobby_id(value : String) -> void:
		__lobby_id.value = value
	
	var __party_id: PBField
	func has_party_id() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_party_id() -> String:
		return __party_id.value
	func clear_party_id() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__party_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_party_id(value : String) -> void:
		__party_id.value = value
	
	var __is_online: PBField
	func has_is_online() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_is_online() -> bool:
		return __is_online.value
	func clear_is_online() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__is_online.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_online(value : bool) -> void:
		__is_online.value = value
	
	var __last_seen_at_ms: PBField
	func has_last_seen_at_ms() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_last_seen_at_ms() -> int:
		return __last_seen_at_ms.value
	func clear_last_seen_at_ms() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__last_seen_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_last_seen_at_ms(value : int) -> void:
		__last_seen_at_ms.value = value
	
	var __linked_providers: PBField
	func has_linked_providers() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_linked_providers() -> LinkedProviders:
		return __linked_providers.value
	func clear_linked_providers() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__linked_providers.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_linked_providers() -> LinkedProviders:
		__linked_providers.value = LinkedProviders.new()
		return __linked_providers.value
	
	var __has_password: PBField
	func has_has_password() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_has_password() -> bool:
		return __has_password.value
	func clear_has_password() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__has_password.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_has_password(value : bool) -> void:
		__has_password.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[12].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[12].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	var __username: PBField
	func has_username() -> bool:
		return data[13].state == PB_SERVICE_STATE.FILLED
	func get_username() -> String:
		return __username.value
	func clear_username() -> void:
		data[13].state = PB_SERVICE_STATE.UNFILLED
		__username.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_username(value : String) -> void:
		__username.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class FriendUpdate:
	extends RefCounted
	func _init():
		var service
		
		var __friends_default: Array = []
		__friends = PBField.new("friends", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 1, true, __friends_default)
		service = PBServiceField.new()
		service.field = __friends
		service.func_ref = Callable(self, "add_empty_friends")
		data[__friends.tag] = service
		
	var data = {}
	
	var __friends: PBField
	func get_raw_friends():
		return __friends.value
	func get_friends():
		return PBPacker.construct_map(__friends.value)
	func clear_friends():
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__friends.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_friends() -> FriendUpdate.map_type_friends:
		var element = FriendUpdate.map_type_friends.new()
		__friends.value.append(element)
		return element
	func add_friends(a_key) -> User:
		var idx = -1
		for i in range(__friends.value.size()):
			if __friends.value[i].get_key() == a_key:
				idx = i
				break
		var element = FriendUpdate.map_type_friends.new()
		element.set_key(a_key)
		if idx != -1:
			__friends.value[idx] = element
		else:
			__friends.value.append(element)
		return element.new_value()
	
	class map_type_friends:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			service.func_ref = Callable(self, "new_value")
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			return data[1].state == PB_SERVICE_STATE.FILLED
		func get_key() -> String:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
		func set_key(value : String) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			return data[2].state == PB_SERVICE_STATE.FILLED
		func get_value() -> User:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		func new_value() -> User:
			__value.value = User.new()
			return __value.value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class UserBrief:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__display_name = PBField.new("display_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __display_name
		data[__display_name.tag] = service
		
		__profile_url = PBField.new("profile_url", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __profile_url
		data[__profile_url.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__is_online = PBField.new("is_online", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_online
		data[__is_online.tag] = service
		
		__is_activated = PBField.new("is_activated", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_activated
		data[__is_activated.tag] = service
		
		__last_seen_at_ms = PBField.new("last_seen_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __last_seen_at_ms
		data[__last_seen_at_ms.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
		__username = PBField.new("username", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __username
		data[__username.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __display_name: PBField
	func has_display_name() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_display_name() -> String:
		return __display_name.value
	func clear_display_name() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__display_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_display_name(value : String) -> void:
		__display_name.value = value
	
	var __profile_url: PBField
	func has_profile_url() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_profile_url() -> String:
		return __profile_url.value
	func clear_profile_url() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__profile_url.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_profile_url(value : String) -> void:
		__profile_url.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __is_online: PBField
	func has_is_online() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_is_online() -> bool:
		return __is_online.value
	func clear_is_online() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__is_online.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_online(value : bool) -> void:
		__is_online.value = value
	
	var __is_activated: PBField
	func has_is_activated() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_is_activated() -> bool:
		return __is_activated.value
	func clear_is_activated() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__is_activated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_activated(value : bool) -> void:
		__is_activated.value = value
	
	var __last_seen_at_ms: PBField
	func has_last_seen_at_ms() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_last_seen_at_ms() -> int:
		return __last_seen_at_ms.value
	func clear_last_seen_at_ms() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__last_seen_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_last_seen_at_ms(value : int) -> void:
		__last_seen_at_ms.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	var __username: PBField
	func has_username() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_username() -> String:
		return __username.value
	func clear_username() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__username.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_username(value : String) -> void:
		__username.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Notification:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__sender_id = PBField.new("sender_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sender_id
		data[__sender_id.tag] = service
		
		__sender_name = PBField.new("sender_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sender_name
		data[__sender_name.tag] = service
		
		__recipient_id = PBField.new("recipient_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __recipient_id
		data[__recipient_id.tag] = service
		
		__title = PBField.new("title", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __title
		data[__title.tag] = service
		
		__content = PBField.new("content", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __content
		data[__content.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__inserted_at_ms = PBField.new("inserted_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __inserted_at_ms
		data[__inserted_at_ms.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __sender_id: PBField
	func has_sender_id() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_sender_id() -> String:
		return __sender_id.value
	func clear_sender_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__sender_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sender_id(value : String) -> void:
		__sender_id.value = value
	
	var __sender_name: PBField
	func has_sender_name() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_sender_name() -> String:
		return __sender_name.value
	func clear_sender_name() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__sender_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sender_name(value : String) -> void:
		__sender_name.value = value
	
	var __recipient_id: PBField
	func has_recipient_id() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_recipient_id() -> String:
		return __recipient_id.value
	func clear_recipient_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__recipient_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_recipient_id(value : String) -> void:
		__recipient_id.value = value
	
	var __title: PBField
	func has_title() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_title() -> String:
		return __title.value
	func clear_title() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__title.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_title(value : String) -> void:
		__title.value = value
	
	var __content: PBField
	func has_content() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_content() -> String:
		return __content.value
	func clear_content() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__content.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_content(value : String) -> void:
		__content.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __inserted_at_ms: PBField
	func has_inserted_at_ms() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_inserted_at_ms() -> int:
		return __inserted_at_ms.value
	func clear_inserted_at_ms() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__inserted_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_inserted_at_ms(value : int) -> void:
		__inserted_at_ms.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class ChatMessage:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__content = PBField.new("content", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __content
		data[__content.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__sender_id = PBField.new("sender_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sender_id
		data[__sender_id.tag] = service
		
		__sender_name = PBField.new("sender_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sender_name
		data[__sender_name.tag] = service
		
		__chat_type = PBField.new("chat_type", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __chat_type
		data[__chat_type.tag] = service
		
		__chat_ref_id = PBField.new("chat_ref_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __chat_ref_id
		data[__chat_ref_id.tag] = service
		
		__inserted_at_ms = PBField.new("inserted_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __inserted_at_ms
		data[__inserted_at_ms.tag] = service
		
		__updated_at_ms = PBField.new("updated_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __updated_at_ms
		data[__updated_at_ms.tag] = service
		
		__sender_email = PBField.new("sender_email", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sender_email
		data[__sender_email.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __content: PBField
	func has_content() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_content() -> String:
		return __content.value
	func clear_content() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__content.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_content(value : String) -> void:
		__content.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __sender_id: PBField
	func has_sender_id() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_sender_id() -> String:
		return __sender_id.value
	func clear_sender_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__sender_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sender_id(value : String) -> void:
		__sender_id.value = value
	
	var __sender_name: PBField
	func has_sender_name() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_sender_name() -> String:
		return __sender_name.value
	func clear_sender_name() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__sender_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sender_name(value : String) -> void:
		__sender_name.value = value
	
	var __chat_type: PBField
	func has_chat_type() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_chat_type() -> String:
		return __chat_type.value
	func clear_chat_type() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__chat_type.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_chat_type(value : String) -> void:
		__chat_type.value = value
	
	var __chat_ref_id: PBField
	func has_chat_ref_id() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_chat_ref_id() -> String:
		return __chat_ref_id.value
	func clear_chat_ref_id() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__chat_ref_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_chat_ref_id(value : String) -> void:
		__chat_ref_id.value = value
	
	var __inserted_at_ms: PBField
	func has_inserted_at_ms() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_inserted_at_ms() -> int:
		return __inserted_at_ms.value
	func clear_inserted_at_ms() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__inserted_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_inserted_at_ms(value : int) -> void:
		__inserted_at_ms.value = value
	
	var __updated_at_ms: PBField
	func has_updated_at_ms() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_updated_at_ms() -> int:
		return __updated_at_ms.value
	func clear_updated_at_ms() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__updated_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_updated_at_ms(value : int) -> void:
		__updated_at_ms.value = value
	
	var __sender_email: PBField
	func has_sender_email() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_sender_email() -> String:
		return __sender_email.value
	func clear_sender_email() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__sender_email.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sender_email(value : String) -> void:
		__sender_email.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class QuestProgress:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__user_id = PBField.new("user_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __user_id
		data[__user_id.tag] = service
		
		__quest_key = PBField.new("quest_key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __quest_key
		data[__quest_key.tag] = service
		
		__period_key = PBField.new("period_key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __period_key
		data[__period_key.tag] = service
		
		var __objective_progress_default: Array = []
		__objective_progress = PBField.new("objective_progress", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 5, true, __objective_progress_default)
		service = PBServiceField.new()
		service.field = __objective_progress
		service.func_ref = Callable(self, "add_empty_objective_progress")
		data[__objective_progress.tag] = service
		
		__status = PBField.new("status", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __status
		data[__status.tag] = service
		
		__completed_at_ms = PBField.new("completed_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __completed_at_ms
		data[__completed_at_ms.tag] = service
		
		__claimed_at_ms = PBField.new("claimed_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __claimed_at_ms
		data[__claimed_at_ms.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__inserted_at_ms = PBField.new("inserted_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __inserted_at_ms
		data[__inserted_at_ms.tag] = service
		
		__updated_at_ms = PBField.new("updated_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __updated_at_ms
		data[__updated_at_ms.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __user_id: PBField
	func has_user_id() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_user_id() -> String:
		return __user_id.value
	func clear_user_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__user_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_user_id(value : String) -> void:
		__user_id.value = value
	
	var __quest_key: PBField
	func has_quest_key() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_quest_key() -> String:
		return __quest_key.value
	func clear_quest_key() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__quest_key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_quest_key(value : String) -> void:
		__quest_key.value = value
	
	var __period_key: PBField
	func has_period_key() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_period_key() -> String:
		return __period_key.value
	func clear_period_key() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__period_key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_period_key(value : String) -> void:
		__period_key.value = value
	
	var __objective_progress: PBField
	func get_raw_objective_progress():
		return __objective_progress.value
	func get_objective_progress():
		return PBPacker.construct_map(__objective_progress.value)
	func clear_objective_progress():
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__objective_progress.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_objective_progress() -> QuestProgress.map_type_objective_progress:
		var element = QuestProgress.map_type_objective_progress.new()
		__objective_progress.value.append(element)
		return element
	func add_objective_progress(a_key, a_value) -> void:
		var idx = -1
		for i in range(__objective_progress.value.size()):
			if __objective_progress.value[i].get_key() == a_key:
				idx = i
				break
		var element = QuestProgress.map_type_objective_progress.new()
		element.set_key(a_key)
		element.set_value(a_value)
		if idx != -1:
			__objective_progress.value[idx] = element
		else:
			__objective_progress.value.append(element)
	
	var __status: PBField
	func has_status() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_status() -> String:
		return __status.value
	func clear_status() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__status.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_status(value : String) -> void:
		__status.value = value
	
	var __completed_at_ms: PBField
	func has_completed_at_ms() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_completed_at_ms() -> int:
		return __completed_at_ms.value
	func clear_completed_at_ms() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__completed_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_completed_at_ms(value : int) -> void:
		__completed_at_ms.value = value
	
	var __claimed_at_ms: PBField
	func has_claimed_at_ms() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_claimed_at_ms() -> int:
		return __claimed_at_ms.value
	func clear_claimed_at_ms() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__claimed_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_claimed_at_ms(value : int) -> void:
		__claimed_at_ms.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __inserted_at_ms: PBField
	func has_inserted_at_ms() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_inserted_at_ms() -> int:
		return __inserted_at_ms.value
	func clear_inserted_at_ms() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__inserted_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_inserted_at_ms(value : int) -> void:
		__inserted_at_ms.value = value
	
	var __updated_at_ms: PBField
	func has_updated_at_ms() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_updated_at_ms() -> int:
		return __updated_at_ms.value
	func clear_updated_at_ms() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__updated_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_updated_at_ms(value : int) -> void:
		__updated_at_ms.value = value
	
	class map_type_objective_progress:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			return data[1].state == PB_SERVICE_STATE.FILLED
		func get_key() -> String:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
		func set_key(value : String) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			return data[2].state == PB_SERVICE_STATE.FILLED
		func get_value() -> int:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
		func set_value(value : int) -> void:
			__value.value = value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Lobby:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__title = PBField.new("title", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __title
		data[__title.tag] = service
		
		__host_id = PBField.new("host_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __host_id
		data[__host_id.tag] = service
		
		__host_name = PBField.new("host_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __host_name
		data[__host_name.tag] = service
		
		__hostless = PBField.new("hostless", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __hostless
		data[__hostless.tag] = service
		
		__max_users = PBField.new("max_users", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __max_users
		data[__max_users.tag] = service
		
		__is_hidden = PBField.new("is_hidden", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_hidden
		data[__is_hidden.tag] = service
		
		__is_locked = PBField.new("is_locked", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_locked
		data[__is_locked.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__is_passworded = PBField.new("is_passworded", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_passworded
		data[__is_passworded.tag] = service
		
		__slowdown = PBField.new("slowdown", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __slowdown
		data[__slowdown.tag] = service
		
		__spectator_count = PBField.new("spectator_count", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 12, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __spectator_count
		data[__spectator_count.tag] = service
		
		var __members_default: Array[UserBrief] = []
		__members = PBField.new("members", PB_DATA_TYPE.MESSAGE, PB_RULE.REPEATED, 13, true, __members_default)
		service = PBServiceField.new()
		service.field = __members
		service.func_ref = Callable(self, "add_members")
		data[__members.tag] = service
		
		__has_members = PBField.new("has_members", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 14, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __has_members
		data[__has_members.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 15, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __title: PBField
	func has_title() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_title() -> String:
		return __title.value
	func clear_title() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__title.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_title(value : String) -> void:
		__title.value = value
	
	var __host_id: PBField
	func has_host_id() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_host_id() -> String:
		return __host_id.value
	func clear_host_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__host_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_host_id(value : String) -> void:
		__host_id.value = value
	
	var __host_name: PBField
	func has_host_name() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_host_name() -> String:
		return __host_name.value
	func clear_host_name() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__host_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_host_name(value : String) -> void:
		__host_name.value = value
	
	var __hostless: PBField
	func has_hostless() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_hostless() -> bool:
		return __hostless.value
	func clear_hostless() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__hostless.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_hostless(value : bool) -> void:
		__hostless.value = value
	
	var __max_users: PBField
	func has_max_users() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_max_users() -> int:
		return __max_users.value
	func clear_max_users() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__max_users.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_max_users(value : int) -> void:
		__max_users.value = value
	
	var __is_hidden: PBField
	func has_is_hidden() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_is_hidden() -> bool:
		return __is_hidden.value
	func clear_is_hidden() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__is_hidden.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_hidden(value : bool) -> void:
		__is_hidden.value = value
	
	var __is_locked: PBField
	func has_is_locked() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_is_locked() -> bool:
		return __is_locked.value
	func clear_is_locked() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__is_locked.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_locked(value : bool) -> void:
		__is_locked.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __is_passworded: PBField
	func has_is_passworded() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_is_passworded() -> bool:
		return __is_passworded.value
	func clear_is_passworded() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__is_passworded.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_passworded(value : bool) -> void:
		__is_passworded.value = value
	
	var __slowdown: PBField
	func has_slowdown() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_slowdown() -> int:
		return __slowdown.value
	func clear_slowdown() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__slowdown.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_slowdown(value : int) -> void:
		__slowdown.value = value
	
	var __spectator_count: PBField
	func has_spectator_count() -> bool:
		return data[12].state == PB_SERVICE_STATE.FILLED
	func get_spectator_count() -> int:
		return __spectator_count.value
	func clear_spectator_count() -> void:
		data[12].state = PB_SERVICE_STATE.UNFILLED
		__spectator_count.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_spectator_count(value : int) -> void:
		__spectator_count.value = value
	
	var __members: PBField
	func get_members() -> Array[UserBrief]:
		return __members.value
	func clear_members() -> void:
		data[13].state = PB_SERVICE_STATE.UNFILLED
		__members.value.clear()
	func add_members() -> UserBrief:
		var element = UserBrief.new()
		__members.value.append(element)
		return element
	
	var __has_members: PBField
	func has_has_members() -> bool:
		return data[14].state == PB_SERVICE_STATE.FILLED
	func get_has_members() -> bool:
		return __has_members.value
	func clear_has_members() -> void:
		data[14].state = PB_SERVICE_STATE.UNFILLED
		__has_members.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_has_members(value : bool) -> void:
		__has_members.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[15].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[15].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Group:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__title = PBField.new("title", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __title
		data[__title.tag] = service
		
		__description = PBField.new("description", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __description
		data[__description.tag] = service
		
		__type = PBField.new("type", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __type
		data[__type.tag] = service
		
		__max_members = PBField.new("max_members", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __max_members
		data[__max_members.tag] = service
		
		__creator_id = PBField.new("creator_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __creator_id
		data[__creator_id.tag] = service
		
		__creator_name = PBField.new("creator_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __creator_name
		data[__creator_name.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__member_count = PBField.new("member_count", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __member_count
		data[__member_count.tag] = service
		
		__slowdown = PBField.new("slowdown", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __slowdown
		data[__slowdown.tag] = service
		
		__inserted_at_ms = PBField.new("inserted_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __inserted_at_ms
		data[__inserted_at_ms.tag] = service
		
		__updated_at_ms = PBField.new("updated_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 12, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __updated_at_ms
		data[__updated_at_ms.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 13, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __title: PBField
	func has_title() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_title() -> String:
		return __title.value
	func clear_title() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__title.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_title(value : String) -> void:
		__title.value = value
	
	var __description: PBField
	func has_description() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_description() -> String:
		return __description.value
	func clear_description() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__description.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_description(value : String) -> void:
		__description.value = value
	
	var __type: PBField
	func has_type() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_type() -> String:
		return __type.value
	func clear_type() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__type.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_type(value : String) -> void:
		__type.value = value
	
	var __max_members: PBField
	func has_max_members() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_max_members() -> int:
		return __max_members.value
	func clear_max_members() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__max_members.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_max_members(value : int) -> void:
		__max_members.value = value
	
	var __creator_id: PBField
	func has_creator_id() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_creator_id() -> String:
		return __creator_id.value
	func clear_creator_id() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__creator_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_creator_id(value : String) -> void:
		__creator_id.value = value
	
	var __creator_name: PBField
	func has_creator_name() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_creator_name() -> String:
		return __creator_name.value
	func clear_creator_name() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__creator_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_creator_name(value : String) -> void:
		__creator_name.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __member_count: PBField
	func has_member_count() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_member_count() -> int:
		return __member_count.value
	func clear_member_count() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__member_count.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_member_count(value : int) -> void:
		__member_count.value = value
	
	var __slowdown: PBField
	func has_slowdown() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_slowdown() -> int:
		return __slowdown.value
	func clear_slowdown() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__slowdown.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_slowdown(value : int) -> void:
		__slowdown.value = value
	
	var __inserted_at_ms: PBField
	func has_inserted_at_ms() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_inserted_at_ms() -> int:
		return __inserted_at_ms.value
	func clear_inserted_at_ms() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__inserted_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_inserted_at_ms(value : int) -> void:
		__inserted_at_ms.value = value
	
	var __updated_at_ms: PBField
	func has_updated_at_ms() -> bool:
		return data[12].state == PB_SERVICE_STATE.FILLED
	func get_updated_at_ms() -> int:
		return __updated_at_ms.value
	func clear_updated_at_ms() -> void:
		data[12].state = PB_SERVICE_STATE.UNFILLED
		__updated_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_updated_at_ms(value : int) -> void:
		__updated_at_ms.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[13].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[13].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class Party:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__leader_id = PBField.new("leader_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __leader_id
		data[__leader_id.tag] = service
		
		__leader_name = PBField.new("leader_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __leader_name
		data[__leader_name.tag] = service
		
		__max_size = PBField.new("max_size", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __max_size
		data[__max_size.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		var __members_default: Array[UserBrief] = []
		__members = PBField.new("members", PB_DATA_TYPE.MESSAGE, PB_RULE.REPEATED, 6, true, __members_default)
		service = PBServiceField.new()
		service.field = __members
		service.func_ref = Callable(self, "add_members")
		data[__members.tag] = service
		
		__has_members = PBField.new("has_members", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __has_members
		data[__has_members.tag] = service
		
		__inserted_at_ms = PBField.new("inserted_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __inserted_at_ms
		data[__inserted_at_ms.tag] = service
		
		__updated_at_ms = PBField.new("updated_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __updated_at_ms
		data[__updated_at_ms.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __leader_id: PBField
	func has_leader_id() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_leader_id() -> String:
		return __leader_id.value
	func clear_leader_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__leader_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_leader_id(value : String) -> void:
		__leader_id.value = value
	
	var __leader_name: PBField
	func has_leader_name() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_leader_name() -> String:
		return __leader_name.value
	func clear_leader_name() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__leader_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_leader_name(value : String) -> void:
		__leader_name.value = value
	
	var __max_size: PBField
	func has_max_size() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_max_size() -> int:
		return __max_size.value
	func clear_max_size() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__max_size.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_max_size(value : int) -> void:
		__max_size.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __members: PBField
	func get_members() -> Array[UserBrief]:
		return __members.value
	func clear_members() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__members.value.clear()
	func add_members() -> UserBrief:
		var element = UserBrief.new()
		__members.value.append(element)
		return element
	
	var __has_members: PBField
	func has_has_members() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_has_members() -> bool:
		return __has_members.value
	func clear_has_members() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__has_members.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_has_members(value : bool) -> void:
		__has_members.value = value
	
	var __inserted_at_ms: PBField
	func has_inserted_at_ms() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_inserted_at_ms() -> int:
		return __inserted_at_ms.value
	func clear_inserted_at_ms() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__inserted_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_inserted_at_ms(value : int) -> void:
		__inserted_at_ms.value = value
	
	var __updated_at_ms: PBField
	func has_updated_at_ms() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_updated_at_ms() -> int:
		return __updated_at_ms.value
	func clear_updated_at_ms() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__updated_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_updated_at_ms(value : int) -> void:
		__updated_at_ms.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class MemberEvent:
	extends RefCounted
	func _init():
		var service
		
		__user_id = PBField.new("user_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __user_id
		data[__user_id.tag] = service
		
		__display_name = PBField.new("display_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __display_name
		data[__display_name.tag] = service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__profile_url = PBField.new("profile_url", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __profile_url
		data[__profile_url.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__is_online = PBField.new("is_online", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_online
		data[__is_online.tag] = service
		
		__is_activated = PBField.new("is_activated", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __is_activated
		data[__is_activated.tag] = service
		
		__last_seen_at_ms = PBField.new("last_seen_at_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __last_seen_at_ms
		data[__last_seen_at_ms.tag] = service
		
		__group_id = PBField.new("group_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __group_id
		data[__group_id.tag] = service
		
		__metadata_pb = PBField.new("metadata_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_pb
		data[__metadata_pb.tag] = service
		
		__username = PBField.new("username", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __username
		data[__username.tag] = service
		
	var data = {}
	
	var __user_id: PBField
	func has_user_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_user_id() -> String:
		return __user_id.value
	func clear_user_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__user_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_user_id(value : String) -> void:
		__user_id.value = value
	
	var __display_name: PBField
	func has_display_name() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_display_name() -> String:
		return __display_name.value
	func clear_display_name() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__display_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_display_name(value : String) -> void:
		__display_name.value = value
	
	var __id: PBField
	func has_id() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	var __profile_url: PBField
	func has_profile_url() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_profile_url() -> String:
		return __profile_url.value
	func clear_profile_url() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__profile_url.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_profile_url(value : String) -> void:
		__profile_url.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __is_online: PBField
	func has_is_online() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_is_online() -> bool:
		return __is_online.value
	func clear_is_online() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__is_online.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_online(value : bool) -> void:
		__is_online.value = value
	
	var __is_activated: PBField
	func has_is_activated() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_is_activated() -> bool:
		return __is_activated.value
	func clear_is_activated() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__is_activated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_is_activated(value : bool) -> void:
		__is_activated.value = value
	
	var __last_seen_at_ms: PBField
	func has_last_seen_at_ms() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_last_seen_at_ms() -> int:
		return __last_seen_at_ms.value
	func clear_last_seen_at_ms() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__last_seen_at_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_last_seen_at_ms(value : int) -> void:
		__last_seen_at_ms.value = value
	
	var __group_id: PBField
	func has_group_id() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_group_id() -> String:
		return __group_id.value
	func clear_group_id() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__group_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_group_id(value : String) -> void:
		__group_id.value = value
	
	var __metadata_pb: PBField
	func has_metadata_pb() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_metadata_pb() -> PackedByteArray:
		return __metadata_pb.value
	func clear_metadata_pb() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__metadata_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_pb(value : PackedByteArray) -> void:
		__metadata_pb.value = value
	
	var __username: PBField
	func has_username() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_username() -> String:
		return __username.value
	func clear_username() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__username.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_username(value : String) -> void:
		__username.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class EntityId:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class PartyRef:
	extends RefCounted
	func _init():
		var service
		
		__party_id = PBField.new("party_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __party_id
		data[__party_id.tag] = service
		
	var data = {}
	
	var __party_id: PBField
	func has_party_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_party_id() -> String:
		return __party_id.value
	func clear_party_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__party_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_party_id(value : String) -> void:
		__party_id.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class HostChanged:
	extends RefCounted
	func _init():
		var service
		
		__new_host_id = PBField.new("new_host_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __new_host_id
		data[__new_host_id.tag] = service
		
		__display_name = PBField.new("display_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __display_name
		data[__display_name.tag] = service
		
	var data = {}
	
	var __new_host_id: PBField
	func has_new_host_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_new_host_id() -> String:
		return __new_host_id.value
	func clear_new_host_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__new_host_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_new_host_id(value : String) -> void:
		__new_host_id.value = value
	
	var __display_name: PBField
	func has_display_name() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_display_name() -> String:
		return __display_name.value
	func clear_display_name() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__display_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_display_name(value : String) -> void:
		__display_name.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class GroupInviteEvent:
	extends RefCounted
	func _init():
		var service
		
		__group_id = PBField.new("group_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __group_id
		data[__group_id.tag] = service
		
	var data = {}
	
	var __group_id: PBField
	func has_group_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_group_id() -> String:
		return __group_id.value
	func clear_group_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__group_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_group_id(value : String) -> void:
		__group_id.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class PartyInviteEvent:
	extends RefCounted
	func _init():
		var service
		
		__party_id = PBField.new("party_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __party_id
		data[__party_id.tag] = service
		
		__user_id = PBField.new("user_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __user_id
		data[__user_id.tag] = service
		
	var data = {}
	
	var __party_id: PBField
	func has_party_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_party_id() -> String:
		return __party_id.value
	func clear_party_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__party_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_party_id(value : String) -> void:
		__party_id.value = value
	
	var __user_id: PBField
	func has_user_id() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_user_id() -> String:
		return __user_id.value
	func clear_user_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__user_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_user_id(value : String) -> void:
		__user_id.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class TournamentEvent:
	extends RefCounted
	func _init():
		var service
		
		__tournament_id = PBField.new("tournament_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __tournament_id
		data[__tournament_id.tag] = service
		
		__slug = PBField.new("slug", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __slug
		data[__slug.tag] = service
		
		__state = PBField.new("state", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __state
		data[__state.tag] = service
		
	var data = {}
	
	var __tournament_id: PBField
	func has_tournament_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_tournament_id() -> String:
		return __tournament_id.value
	func clear_tournament_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__tournament_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_tournament_id(value : String) -> void:
		__tournament_id.value = value
	
	var __slug: PBField
	func has_slug() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_slug() -> String:
		return __slug.value
	func clear_slug() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__slug.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_slug(value : String) -> void:
		__slug.value = value
	
	var __state: PBField
	func has_state() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_state() -> String:
		return __state.value
	func clear_state() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__state.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_state(value : String) -> void:
		__state.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class TournamentMatchEvent:
	extends RefCounted
	func _init():
		var service
		
		__tournament_id = PBField.new("tournament_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __tournament_id
		data[__tournament_id.tag] = service
		
		__slug = PBField.new("slug", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __slug
		data[__slug.tag] = service
		
		__match_id = PBField.new("match_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __match_id
		data[__match_id.tag] = service
		
		__round = PBField.new("round", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __round
		data[__round.tag] = service
		
		__deadline_ms = PBField.new("deadline_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __deadline_ms
		data[__deadline_ms.tag] = service
		
		__winner_entry_id = PBField.new("winner_entry_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __winner_entry_id
		data[__winner_entry_id.tag] = service
		
	var data = {}
	
	var __tournament_id: PBField
	func has_tournament_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_tournament_id() -> String:
		return __tournament_id.value
	func clear_tournament_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__tournament_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_tournament_id(value : String) -> void:
		__tournament_id.value = value
	
	var __slug: PBField
	func has_slug() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_slug() -> String:
		return __slug.value
	func clear_slug() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__slug.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_slug(value : String) -> void:
		__slug.value = value
	
	var __match_id: PBField
	func has_match_id() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_match_id() -> String:
		return __match_id.value
	func clear_match_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__match_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_match_id(value : String) -> void:
		__match_id.value = value
	
	var __round: PBField
	func has_round() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_round() -> int:
		return __round.value
	func clear_round() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__round.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_round(value : int) -> void:
		__round.value = value
	
	var __deadline_ms: PBField
	func has_deadline_ms() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_deadline_ms() -> int:
		return __deadline_ms.value
	func clear_deadline_ms() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__deadline_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_deadline_ms(value : int) -> void:
		__deadline_ms.value = value
	
	var __winner_entry_id: PBField
	func has_winner_entry_id() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_winner_entry_id() -> String:
		return __winner_entry_id.value
	func clear_winner_entry_id() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__winner_entry_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_winner_entry_id(value : String) -> void:
		__winner_entry_id.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class MatchmakingFound:
	extends RefCounted
	func _init():
		var service
		
		__lobby_id = PBField.new("lobby_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __lobby_id
		data[__lobby_id.tag] = service
		
		var __match_params_default: Array = []
		__match_params = PBField.new("match_params", PB_DATA_TYPE.MAP, PB_RULE.REPEATED, 2, true, __match_params_default)
		service = PBServiceField.new()
		service.field = __match_params
		service.func_ref = Callable(self, "add_empty_match_params")
		data[__match_params.tag] = service
		
	var data = {}
	
	var __lobby_id: PBField
	func has_lobby_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_lobby_id() -> String:
		return __lobby_id.value
	func clear_lobby_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__lobby_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_lobby_id(value : String) -> void:
		__lobby_id.value = value
	
	var __match_params: PBField
	func get_raw_match_params():
		return __match_params.value
	func get_match_params():
		return PBPacker.construct_map(__match_params.value)
	func clear_match_params():
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__match_params.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MAP]
	func add_empty_match_params() -> MatchmakingFound.map_type_match_params:
		var element = MatchmakingFound.map_type_match_params.new()
		__match_params.value.append(element)
		return element
	func add_match_params(a_key, a_value) -> void:
		var idx = -1
		for i in range(__match_params.value.size()):
			if __match_params.value[i].get_key() == a_key:
				idx = i
				break
		var element = MatchmakingFound.map_type_match_params.new()
		element.set_key(a_key)
		element.set_value(a_value)
		if idx != -1:
			__match_params.value[idx] = element
		else:
			__match_params.value.append(element)
	
	class map_type_match_params:
		extends RefCounted
		func _init():
			var service
			
			__key = PBField.new("key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
			__key.is_map_field = true
			service = PBServiceField.new()
			service.field = __key
			data[__key.tag] = service
			
			__value = PBField.new("value", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
			__value.is_map_field = true
			service = PBServiceField.new()
			service.field = __value
			data[__value.tag] = service
			
		var data = {}
		
		var __key: PBField
		func has_key() -> bool:
			return data[1].state == PB_SERVICE_STATE.FILLED
		func get_key() -> String:
			return __key.value
		func clear_key() -> void:
			data[1].state = PB_SERVICE_STATE.UNFILLED
			__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
		func set_key(value : String) -> void:
			__key.value = value
		
		var __value: PBField
		func has_value() -> bool:
			return data[2].state == PB_SERVICE_STATE.FILLED
		func get_value() -> String:
			return __value.value
		func clear_value() -> void:
			data[2].state = PB_SERVICE_STATE.UNFILLED
			__value.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
		func set_value(value : String) -> void:
			__value.value = value
		
		func _to_string() -> String:
			return PBPacker.message_to_string(data)
			
		func to_bytes() -> PackedByteArray:
			return PBPacker.pack_message(data)
			
		func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
			var cur_limit = bytes.size()
			if limit != -1:
				cur_limit = limit
			var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
			if result == cur_limit:
				if PBPacker.check_required(data):
					if limit == -1:
						return PB_ERR.NO_ERRORS
				else:
					return PB_ERR.REQUIRED_FIELDS
			elif limit == -1 && result > 0:
				return PB_ERR.PARSE_INCOMPLETE
			return result
		
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class ReadyCheckParticipant:
	extends RefCounted
	func _init():
		var service
		
		__user_id = PBField.new("user_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __user_id
		data[__user_id.tag] = service
		
		__display_name = PBField.new("display_name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __display_name
		data[__display_name.tag] = service
		
		__state = PBField.new("state", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __state
		data[__state.tag] = service
		
	var data = {}
	
	var __user_id: PBField
	func has_user_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_user_id() -> String:
		return __user_id.value
	func clear_user_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__user_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_user_id(value : String) -> void:
		__user_id.value = value
	
	var __display_name: PBField
	func has_display_name() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_display_name() -> String:
		return __display_name.value
	func clear_display_name() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__display_name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_display_name(value : String) -> void:
		__display_name.value = value
	
	var __state: PBField
	func has_state() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_state() -> String:
		return __state.value
	func clear_state() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__state.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_state(value : String) -> void:
		__state.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class ReadyCheckState:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__kind = PBField.new("kind", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __kind
		data[__kind.tag] = service
		
		__status = PBField.new("status", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __status
		data[__status.tag] = service
		
		__lobby_id = PBField.new("lobby_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __lobby_id
		data[__lobby_id.tag] = service
		
		__deadline_ms = PBField.new("deadline_ms", PB_DATA_TYPE.INT64, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT64])
		service = PBServiceField.new()
		service.field = __deadline_ms
		data[__deadline_ms.tag] = service
		
		__total = PBField.new("total", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __total
		data[__total.tag] = service
		
		__ready_count = PBField.new("ready_count", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __ready_count
		data[__ready_count.tag] = service
		
		__your_state = PBField.new("your_state", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __your_state
		data[__your_state.tag] = service
		
		__reason = PBField.new("reason", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __reason
		data[__reason.tag] = service
		
		var __participants_default: Array[ReadyCheckParticipant] = []
		__participants = PBField.new("participants", PB_DATA_TYPE.MESSAGE, PB_RULE.REPEATED, 10, true, __participants_default)
		service = PBServiceField.new()
		service.field = __participants
		service.func_ref = Callable(self, "add_participants")
		data[__participants.tag] = service

		__party_id = PBField.new("party_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __party_id
		data[__party_id.tag] = service

	var data = {}

	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> String:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_id(value : String) -> void:
		__id.value = value

	var __kind: PBField
	func has_kind() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_kind() -> String:
		return __kind.value
	func clear_kind() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__kind.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_kind(value : String) -> void:
		__kind.value = value
	
	var __status: PBField
	func has_status() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_status() -> String:
		return __status.value
	func clear_status() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__status.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_status(value : String) -> void:
		__status.value = value
	
	var __lobby_id: PBField
	func has_lobby_id() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_lobby_id() -> String:
		return __lobby_id.value
	func clear_lobby_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__lobby_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_lobby_id(value : String) -> void:
		__lobby_id.value = value
	
	var __deadline_ms: PBField
	func has_deadline_ms() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_deadline_ms() -> int:
		return __deadline_ms.value
	func clear_deadline_ms() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__deadline_ms.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT64]
	func set_deadline_ms(value : int) -> void:
		__deadline_ms.value = value
	
	var __total: PBField
	func has_total() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_total() -> int:
		return __total.value
	func clear_total() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__total.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_total(value : int) -> void:
		__total.value = value
	
	var __ready_count: PBField
	func has_ready_count() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_ready_count() -> int:
		return __ready_count.value
	func clear_ready_count() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__ready_count.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_ready_count(value : int) -> void:
		__ready_count.value = value
	
	var __your_state: PBField
	func has_your_state() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_your_state() -> String:
		return __your_state.value
	func clear_your_state() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__your_state.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_your_state(value : String) -> void:
		__your_state.value = value
	
	var __reason: PBField
	func has_reason() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_reason() -> String:
		return __reason.value
	func clear_reason() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__reason.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_reason(value : String) -> void:
		__reason.value = value
	
	var __participants: PBField
	func get_participants() -> Array[ReadyCheckParticipant]:
		return __participants.value
	func clear_participants() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__participants.value.clear()
	func add_participants() -> ReadyCheckParticipant:
		var element = ReadyCheckParticipant.new()
		__participants.value.append(element)
		return element

	var __party_id: PBField
	func has_party_id() -> bool:
		return data[11].state == PB_SERVICE_STATE.FILLED
	func get_party_id() -> String:
		return __party_id.value
	func clear_party_id() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__party_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_party_id(value : String) -> void:
		__party_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class KvEntry:
	extends RefCounted
	func _init():
		var service
		
		__key = PBField.new("key", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __key
		data[__key.tag] = service
		
		__user_id = PBField.new("user_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __user_id
		data[__user_id.tag] = service
		
		__lobby_id = PBField.new("lobby_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __lobby_id
		data[__lobby_id.tag] = service
		
		__data_json = PBField.new("data_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __data_json
		data[__data_json.tag] = service
		
		__metadata_json = PBField.new("metadata_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __metadata_json
		data[__metadata_json.tag] = service
		
		__data_pb = PBField.new("data_pb", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __data_pb
		data[__data_pb.tag] = service
		
	var data = {}
	
	var __key: PBField
	func has_key() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_key() -> String:
		return __key.value
	func clear_key() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__key.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_key(value : String) -> void:
		__key.value = value
	
	var __user_id: PBField
	func has_user_id() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_user_id() -> String:
		return __user_id.value
	func clear_user_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__user_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_user_id(value : String) -> void:
		__user_id.value = value
	
	var __lobby_id: PBField
	func has_lobby_id() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_lobby_id() -> String:
		return __lobby_id.value
	func clear_lobby_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__lobby_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_lobby_id(value : String) -> void:
		__lobby_id.value = value
	
	var __data_json: PBField
	func has_data_json() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_data_json() -> PackedByteArray:
		return __data_json.value
	func clear_data_json() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__data_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_data_json(value : PackedByteArray) -> void:
		__data_json.value = value
	
	var __metadata_json: PBField
	func has_metadata_json() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_metadata_json() -> PackedByteArray:
		return __metadata_json.value
	func clear_metadata_json() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__metadata_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_metadata_json(value : PackedByteArray) -> void:
		__metadata_json.value = value
	
	var __data_pb: PBField
	func has_data_pb() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_data_pb() -> PackedByteArray:
		return __data_pb.value
	func clear_data_pb() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__data_pb.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_data_pb(value : PackedByteArray) -> void:
		__data_pb.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RpcCall:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__plugin = PBField.new("plugin", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __plugin
		data[__plugin.tag] = service
		
		__fn = PBField.new("fn", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __fn
		data[__fn.tag] = service
		
		__args_json = PBField.new("args_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __args_json
		data[__args_json.tag] = service
		
		__args_raw = PBField.new("args_raw", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __args_raw
		data[__args_raw.tag] = service
		
	var data = {}
	
	enum ArgsCase {
		ARGS_NOT_SET = 0,
		ARGS_JSON = 4,
		ARGS_RAW = 5,
	}
	var _args_case: int = 0

	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> int:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_id(value : int) -> void:
		__id.value = value
	
	var __plugin: PBField
	func has_plugin() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_plugin() -> String:
		return __plugin.value
	func clear_plugin() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__plugin.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_plugin(value : String) -> void:
		__plugin.value = value
	
	var __fn: PBField
	func has_fn() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_fn() -> String:
		return __fn.value
	func clear_fn() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__fn.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_fn(value : String) -> void:
		__fn.value = value
	
	var __args_json: PBField
	func has_args_json() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_args_json() -> PackedByteArray:
		return __args_json.value
	func clear_args_json() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		_args_case = 0
		__args_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_args_json(value : PackedByteArray) -> void:
		data[4].state = PB_SERVICE_STATE.FILLED
		_args_case = 4
		__args_raw.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__args_json.value = value
	
	var __args_raw: PBField
	func has_args_raw() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_args_raw() -> PackedByteArray:
		return __args_raw.value
	func clear_args_raw() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		_args_case = 0
		__args_raw.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_args_raw(value : PackedByteArray) -> void:
		__args_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		data[5].state = PB_SERVICE_STATE.FILLED
		_args_case = 5
		__args_raw.value = value
	
	func get_args_case() -> int:
		return _args_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RpcReply:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__data_json = PBField.new("data_json", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __data_json
		data[__data_json.tag] = service
		
		__data_raw = PBField.new("data_raw", PB_DATA_TYPE.BYTES, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES])
		service = PBServiceField.new()
		service.field = __data_raw
		data[__data_raw.tag] = service
		
	var data = {}
	
	enum DataCase {
		DATA_NOT_SET = 0,
		DATA_JSON = 2,
		DATA_RAW = 3,
	}
	var _data_case: int = 0

	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> int:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_id(value : int) -> void:
		__id.value = value
	
	var __data_json: PBField
	func has_data_json() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_data_json() -> PackedByteArray:
		return __data_json.value
	func clear_data_json() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		_data_case = 0
		__data_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_data_json(value : PackedByteArray) -> void:
		data[2].state = PB_SERVICE_STATE.FILLED
		_data_case = 2
		__data_raw.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__data_json.value = value
	
	var __data_raw: PBField
	func has_data_raw() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_data_raw() -> PackedByteArray:
		return __data_raw.value
	func clear_data_raw() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		_data_case = 0
		__data_raw.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
	func set_data_raw(value : PackedByteArray) -> void:
		__data_json.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BYTES]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_data_case = 3
		__data_raw.value = value
	
	func get_data_case() -> int:
		return _data_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RpcError:
	extends RefCounted
	func _init():
		var service
		
		__id = PBField.new("id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service
		
		__error = PBField.new("error", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __error
		data[__error.tag] = service
		
	var data = {}
	
	var __id: PBField
	func has_id() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_id() -> int:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_id(value : int) -> void:
		__id.value = value
	
	var __error: PBField
	func has_error() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_error() -> String:
		return __error.value
	func clear_error() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_error(value : String) -> void:
		__error.value = value
	
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
class RtcEnvelope:
	extends RefCounted
	func _init():
		var service
		
		__call_hook = PBField.new("call_hook", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __call_hook
		service.func_ref = Callable(self, "new_call_hook")
		data[__call_hook.tag] = service
		
		__hook_reply = PBField.new("hook_reply", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __hook_reply
		service.func_ref = Callable(self, "new_hook_reply")
		data[__hook_reply.tag] = service
		
		__hook_error = PBField.new("hook_error", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __hook_error
		service.func_ref = Callable(self, "new_hook_error")
		data[__hook_error.tag] = service
		
	var data = {}
	
	enum MsgCase {
		MSG_NOT_SET = 0,
		CALL_HOOK = 1,
		HOOK_REPLY = 2,
		HOOK_ERROR = 3,
	}
	var _msg_case: int = 0

	var __call_hook: PBField
	func has_call_hook() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_call_hook() -> RpcCall:
		return __call_hook.value
	func clear_call_hook() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__call_hook.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_call_hook() -> RpcCall:
		data[1].state = PB_SERVICE_STATE.FILLED
		_msg_case = 1
		__hook_reply.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__hook_error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__call_hook.value = RpcCall.new()
		return __call_hook.value
	
	var __hook_reply: PBField
	func has_hook_reply() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_hook_reply() -> RpcReply:
		return __hook_reply.value
	func clear_hook_reply() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__hook_reply.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_hook_reply() -> RpcReply:
		__call_hook.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		data[2].state = PB_SERVICE_STATE.FILLED
		_msg_case = 2
		__hook_error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__hook_reply.value = RpcReply.new()
		return __hook_reply.value
	
	var __hook_error: PBField
	func has_hook_error() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_hook_error() -> RpcError:
		return __hook_error.value
	func clear_hook_error() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__hook_error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_hook_error() -> RpcError:
		__call_hook.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__hook_reply.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_msg_case = 3
		__hook_error.value = RpcError.new()
		return __hook_error.value
	
	func get_msg_case() -> int:
		return _msg_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)
		
	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)
		
	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result
	
################ USER DATA END #################
