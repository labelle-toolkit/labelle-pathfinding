//! Comptime ZON coercion utilities
//!
//! Converts anonymous structs from .zon files to typed structs at comptime.
//! Handles nested struct coercion, tuple-to-slice conversion, and union coercion.
//!
//! Usage:
//!   const MyType = zon.buildStruct(TargetType, zon_data);
//!   const field_val = zon.coerceValue(FieldType, zon_value);

const std = @import("std");

/// Coerce a comptime ZON value to the expected field type.
/// Handles nested struct coercion and tuple-to-slice conversion.
pub fn coerceValue(comptime FieldType: type, comptime data_value: anytype) FieldType {
    const DataType = @TypeOf(data_value);
    const field_info = @typeInfo(FieldType);

    // Handle optional types - unwrap and coerce the child type
    if (field_info == .optional) {
        const ChildType = field_info.optional.child;
        // Check for null
        if (DataType == @TypeOf(null)) {
            return null;
        }
        // Coerce to the child type and wrap in optional
        return coerceValue(ChildType, data_value);
    }

    // Handle slice types
    if (field_info == .pointer) {
        const ptr_info = field_info.pointer;
        if (ptr_info.size == .slice) {
            const ChildType = ptr_info.child;
            const data_info = @typeInfo(DataType);

            // If data is a tuple, convert to slice
            if (data_info == .@"struct" and data_info.@"struct".is_tuple) {
                return tupleToSlice(ChildType, data_value);
            }
        }
    }

    // Handle fixed-size array coercion (tuple to array)
    if (field_info == .array) {
        const arr_info = field_info.array;
        const data_info = @typeInfo(DataType);
        if (data_info == .@"struct" and data_info.@"struct".is_tuple) {
            const tuple_len = data_info.@"struct".fields.len;
            if (tuple_len != arr_info.len) {
                @compileError(std.fmt.comptimePrint(
                    "Array size mismatch: expected {d} elements, got {d}",
                    .{ arr_info.len, tuple_len },
                ));
            }
            var array: [arr_info.len]arr_info.child = undefined;
            inline for (0..arr_info.len) |i| {
                array[i] = coerceValue(arr_info.child, data_value[i]);
            }
            return array;
        }
    }

    // Handle tagged union coercion from anonymous struct
    // Example: .{ .box = .{ .width = 50, .height = 50 } } -> Shape union
    if (field_info == .@"union") {
        return coerceToUnion(FieldType, data_value);
    }

    // Handle nested struct coercion
    if (field_info == .@"struct" and @typeInfo(DataType) == .@"struct") {
        return buildStruct(FieldType, data_value);
    }

    // Direct assignment for compatible types
    return data_value;
}

/// Coerce a comptime value to a tagged union type.
/// Supports:
/// - Single-field anonymous struct: .{ .box = .{ .width = 50 } } -> Union.box
/// - Enum literal for void payloads: .idle -> State.idle
/// - Payload-matching struct: .{ .width = 50, .height = 50 } -> Container.explicit (if fields match)
fn coerceToUnion(comptime UnionType: type, comptime data_value: anytype) UnionType {
    const DataType = @TypeOf(data_value);
    const data_info = @typeInfo(DataType);
    const union_info = @typeInfo(UnionType).@"union";

    // Case 1: Enum literal for void payload variants
    // Example: .idle -> State.idle (where State = union(enum) { idle, running, ... })
    if (data_info == .enum_literal) {
        const tag_name = @tagName(data_value);

        inline for (union_info.fields) |union_field| {
            if (comptime std.mem.eql(u8, union_field.name, tag_name)) {
                // Verify the payload is void
                if (union_field.type != void) {
                    @compileError("Cannot use enum literal for union variant '" ++ tag_name ++
                        "' with non-void payload. Use .{ ." ++ tag_name ++ " = ... } syntax instead.");
                }
                return @unionInit(UnionType, tag_name, {});
            }
        }
        @compileError("No union variant named '" ++ tag_name ++ "' in " ++ @typeName(UnionType));
    }

    // Case 2: Anonymous struct - could be variant selector or direct payload
    if (data_info == .@"struct") {
        const data_fields = data_info.@"struct".fields;

        // Case 2a: Single-field struct where field name matches a union variant
        // Example: .{ .box = .{ .width = 50, .height = 50 } } -> Shape.box
        if (data_fields.len == 1) {
            const field_name = data_fields[0].name;

            // Check if this field name matches a union variant
            inline for (union_info.fields) |union_field| {
                if (comptime std.mem.eql(u8, union_field.name, field_name)) {
                    // This is the variant selector pattern
                    const variant_value = @field(data_value, field_name);
                    const coerced_payload = coerceValue(union_field.type, variant_value);
                    return @unionInit(UnionType, field_name, coerced_payload);
                }
            }
        }

        // Case 2b: Multi-field struct that matches a union variant's payload type
        // Example: .{ .width = 400, .height = 300 } -> Container.explicit
        inline for (union_info.fields) |union_field| {
            const payload_info = @typeInfo(union_field.type);
            if (payload_info == .@"struct") {
                // Check if data fields are compatible with this payload struct
                if (comptime structFieldsCompatible(DataType, union_field.type)) {
                    const coerced_payload = buildStruct(union_field.type, data_value);
                    return @unionInit(UnionType, union_field.name, coerced_payload);
                }
            }
        }

        @compileError("Cannot coerce struct to union type " ++ @typeName(UnionType) ++
            ". Use .{ .variant_name = payload } syntax or ensure struct fields match a variant's payload.");
    }

    // Case 3: Direct assignment if types match
    if (DataType == UnionType) {
        return data_value;
    }

    @compileError("Cannot coerce " ++ @typeName(DataType) ++ " to union type " ++ @typeName(UnionType) ++
        ". Use .{ .variant_name = payload } or .variant_name (for void payloads).");
}

/// Check if all fields in DataType exist in TargetType (for struct compatibility)
fn structFieldsCompatible(comptime DataType: type, comptime TargetType: type) bool {
    const data_fields = @typeInfo(DataType).@"struct".fields;
    const target_fields = @typeInfo(TargetType).@"struct".fields;

    // All data fields must exist in target
    for (data_fields) |df| {
        var found = false;
        for (target_fields) |tf| {
            if (std.mem.eql(u8, df.name, tf.name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    return data_fields.len > 0;
}

/// Build a struct from comptime anonymous struct data.
/// Recursively coerces nested fields.
/// Raises compile error for missing required fields (fields without defaults).
pub fn buildStruct(comptime StructType: type, comptime data: anytype) StructType {
    return buildStructWithContext(StructType, data, "struct");
}

/// Build a struct with a custom context string for error messages.
fn buildStructWithContext(comptime StructType: type, comptime data: anytype, comptime context: []const u8) StructType {
    const fields = std.meta.fields(StructType);
    var result: StructType = undefined;

    inline for (fields) |field| {
        if (@hasField(@TypeOf(data), field.name)) {
            const data_value = @field(data, field.name);
            @field(result, field.name) = coerceValue(field.type, data_value);
        } else if (field.default_value_ptr) |ptr| {
            const default_ptr: *const field.type = @ptrCast(@alignCast(ptr));
            @field(result, field.name) = default_ptr.*;
        } else {
            @compileError("Missing required field '" ++ field.name ++ "' for " ++ context ++ " '" ++ @typeName(StructType) ++ "'");
        }
    }

    return result;
}

/// Convert a tuple to a slice at comptime.
/// Recursively coerces each element.
pub fn tupleToSlice(comptime ChildType: type, comptime tuple: anytype) []const ChildType {
    const tuple_info = @typeInfo(@TypeOf(tuple)).@"struct";
    const len = tuple_info.fields.len;

    const array = comptime blk: {
        var arr: [len]ChildType = undefined;
        for (0..len) |i| {
            arr[i] = coerceValue(ChildType, tuple[i]);
        }
        break :blk arr;
    };

    return &array;
}

/// Merge two comptime structs, with overrides taking precedence.
/// Returns a new anonymous struct with all fields from base, plus any
/// fields from overrides (which override base values).
///
/// Example:
///   base = .{ .x = 10, .y = 20, .color = .red }
///   overrides = .{ .color = .blue }
///   result = .{ .x = 10, .y = 20, .color = .blue }
pub fn mergeStructs(comptime base: anytype, comptime overrides: anytype) MergedStructType(@TypeOf(base), @TypeOf(overrides)) {
    const BaseType = @TypeOf(base);
    const OverridesType = @TypeOf(overrides);

    var result: MergedStructType(BaseType, OverridesType) = undefined;

    // Copy all fields from base
    inline for (std.meta.fields(BaseType)) |field| {
        if (@hasField(OverridesType, field.name)) {
            @field(result, field.name) = @field(overrides, field.name);
        } else {
            @field(result, field.name) = @field(base, field.name);
        }
    }

    // Add fields that exist only in overrides (not in base)
    inline for (std.meta.fields(OverridesType)) |field| {
        if (!@hasField(BaseType, field.name)) {
            @field(result, field.name) = @field(overrides, field.name);
        }
    }

    return result;
}

/// Compute the merged struct type from two struct types.
fn MergedStructType(comptime BaseType: type, comptime OverridesType: type) type {
    const base_fields = std.meta.fields(BaseType);
    const override_fields = std.meta.fields(OverridesType);

    comptime var field_count = base_fields.len;
    inline for (override_fields) |of| {
        if (!@hasField(BaseType, of.name)) {
            field_count += 1;
        }
    }

    comptime var field_names: [field_count][]const u8 = undefined;
    comptime var field_types: [field_count]type = undefined;
    comptime var field_attrs: [field_count]std.builtin.Type.StructField.Attributes = undefined;
    comptime var i = 0;

    inline for (base_fields) |bf| {
        if (@hasField(OverridesType, bf.name)) {
            inline for (override_fields) |of| {
                if (comptime std.mem.eql(u8, of.name, bf.name)) {
                    field_names[i] = bf.name;
                    field_types[i] = of.type;
                    field_attrs[i] = .{ .@"align" = @alignOf(of.type) };
                }
            }
        } else {
            field_names[i] = bf.name;
            field_types[i] = bf.type;
            field_attrs[i] = .{ .@"align" = @alignOf(bf.type) };
        }
        i += 1;
    }

    inline for (override_fields) |of| {
        if (!@hasField(BaseType, of.name)) {
            field_names[i] = of.name;
            field_types[i] = of.type;
            field_attrs[i] = .{ .@"align" = @alignOf(of.type) };
            i += 1;
        }
    }

    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
}

/// Check if a struct type has any fields
pub fn hasFields(comptime T: type) bool {
    return std.meta.fields(T).len > 0;
}
