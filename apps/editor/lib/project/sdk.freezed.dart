// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sdk.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SdkInfo {

 String? get version; SdkSource get source;/// The SDK's folder, when the source names one (fvm, `FLUTTER_ROOT`);
/// null for `flutter` on `PATH`, which runs by name.
 String? get root;
/// Create a copy of SdkInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SdkInfoCopyWith<SdkInfo> get copyWith => _$SdkInfoCopyWithImpl<SdkInfo>(this as SdkInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SdkInfo&&(identical(other.version, version) || other.version == version)&&(identical(other.source, source) || other.source == source)&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,version,source,root);

@override
String toString() {
  return 'SdkInfo(version: $version, source: $source, root: $root)';
}


}

/// @nodoc
abstract mixin class $SdkInfoCopyWith<$Res>  {
  factory $SdkInfoCopyWith(SdkInfo value, $Res Function(SdkInfo) _then) = _$SdkInfoCopyWithImpl;
@useResult
$Res call({
 String? version, SdkSource source, String? root
});




}
/// @nodoc
class _$SdkInfoCopyWithImpl<$Res>
    implements $SdkInfoCopyWith<$Res> {
  _$SdkInfoCopyWithImpl(this._self, this._then);

  final SdkInfo _self;
  final $Res Function(SdkInfo) _then;

/// Create a copy of SdkInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = freezed,Object? source = null,Object? root = freezed,}) {
  return _then(_self.copyWith(
version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SdkSource,root: freezed == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SdkInfo].
extension SdkInfoPatterns on SdkInfo {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SdkInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SdkInfo() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SdkInfo value)  $default,){
final _that = this;
switch (_that) {
case _SdkInfo():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SdkInfo value)?  $default,){
final _that = this;
switch (_that) {
case _SdkInfo() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? version,  SdkSource source,  String? root)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SdkInfo() when $default != null:
return $default(_that.version,_that.source,_that.root);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? version,  SdkSource source,  String? root)  $default,) {final _that = this;
switch (_that) {
case _SdkInfo():
return $default(_that.version,_that.source,_that.root);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? version,  SdkSource source,  String? root)?  $default,) {final _that = this;
switch (_that) {
case _SdkInfo() when $default != null:
return $default(_that.version,_that.source,_that.root);case _:
  return null;

}
}

}

/// @nodoc


class _SdkInfo implements SdkInfo {
  const _SdkInfo({required this.version, required this.source, this.root});
  

@override final  String? version;
@override final  SdkSource source;
/// The SDK's folder, when the source names one (fvm, `FLUTTER_ROOT`);
/// null for `flutter` on `PATH`, which runs by name.
@override final  String? root;

/// Create a copy of SdkInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SdkInfoCopyWith<_SdkInfo> get copyWith => __$SdkInfoCopyWithImpl<_SdkInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SdkInfo&&(identical(other.version, version) || other.version == version)&&(identical(other.source, source) || other.source == source)&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,version,source,root);

@override
String toString() {
  return 'SdkInfo(version: $version, source: $source, root: $root)';
}


}

/// @nodoc
abstract mixin class _$SdkInfoCopyWith<$Res> implements $SdkInfoCopyWith<$Res> {
  factory _$SdkInfoCopyWith(_SdkInfo value, $Res Function(_SdkInfo) _then) = __$SdkInfoCopyWithImpl;
@override @useResult
$Res call({
 String? version, SdkSource source, String? root
});




}
/// @nodoc
class __$SdkInfoCopyWithImpl<$Res>
    implements _$SdkInfoCopyWith<$Res> {
  __$SdkInfoCopyWithImpl(this._self, this._then);

  final _SdkInfo _self;
  final $Res Function(_SdkInfo) _then;

/// Create a copy of SdkInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = freezed,Object? source = null,Object? root = freezed,}) {
  return _then(_SdkInfo(
version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SdkSource,root: freezed == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
