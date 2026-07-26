/*eslint-disable block-scoped-var, id-length, no-control-regex, no-magic-numbers, no-mixed-operators, no-prototype-builtins, no-redeclare, no-shadow, no-var, sort-vars, default-case, jsdoc/require-param*/
import $protobuf from "protobufjs/minimal.js";

// Common aliases
const $Reader = $protobuf.Reader, $Writer = $protobuf.Writer, $util = $protobuf.util;
const $Object = $util.global.Object, $undefined = $util.global.undefined, $Error = $util.global.Error, $TypeError = $util.global.TypeError, $Boolean = $util.global.Boolean, $String = $util.global.String, $parseInt = $util.global.parseInt, $Array = $util.global.Array, $BigInt = $util.global.BigInt, $Number = $util.global.Number;

// Exported root namespace
const $root = $protobuf.roots["default"] || ($protobuf.roots["default"] = {});

export const gamend = $root.gamend = (() => {

    /**
     * Namespace gamend.
     * @exports gamend
     * @namespace
     */
    const gamend = {};

    gamend.realtime = (function() {

        /**
         * Namespace realtime.
         * @memberof gamend
         * @namespace
         */
        const realtime = {};

        realtime.v1 = (function() {

            /**
             * Namespace v1.
             * @memberof gamend.realtime
             * @namespace
             */
            const v1 = {};

            v1.LinkedProviders = (function() {

                /**
                 * Properties of a LinkedProviders.
                 * @typedef {Object} gamend.realtime.v1.LinkedProviders.$Properties
                 * @property {boolean|null} [google] LinkedProviders google
                 * @property {boolean|null} [facebook] LinkedProviders facebook
                 * @property {boolean|null} [discord] LinkedProviders discord
                 * @property {boolean|null} [apple] LinkedProviders apple
                 * @property {boolean|null} [steam] LinkedProviders steam
                 * @property {boolean|null} [device] LinkedProviders device
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a LinkedProviders.
                 * @memberof gamend.realtime.v1
                 * @interface ILinkedProviders
                 * @augments gamend.realtime.v1.LinkedProviders.$Properties
                 * @deprecated Use gamend.realtime.v1.LinkedProviders.$Properties instead.
                 */

                /**
                 * Shape of a LinkedProviders.
                 * @typedef {gamend.realtime.v1.LinkedProviders.$Properties} gamend.realtime.v1.LinkedProviders.$Shape
                 */

                /**
                 * Constructs a new LinkedProviders.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a LinkedProviders.
                 * @constructor
                 * @param {gamend.realtime.v1.LinkedProviders.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const LinkedProviders = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * LinkedProviders google.
                 * @member {boolean} google
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.google = false;

                /**
                 * LinkedProviders facebook.
                 * @member {boolean} facebook
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.facebook = false;

                /**
                 * LinkedProviders discord.
                 * @member {boolean} discord
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.discord = false;

                /**
                 * LinkedProviders apple.
                 * @member {boolean} apple
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.apple = false;

                /**
                 * LinkedProviders steam.
                 * @member {boolean} steam
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.steam = false;

                /**
                 * LinkedProviders device.
                 * @member {boolean} device
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 */
                LinkedProviders.prototype.device = false;

                /**
                 * Encodes the specified LinkedProviders message. Does not implicitly {@link gamend.realtime.v1.LinkedProviders.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @static
                 * @param {gamend.realtime.v1.LinkedProviders.$Properties} message LinkedProviders message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                LinkedProviders.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.google != null && $Object.hasOwnProperty.call(message, "google") && message.google !== false)
                        writer.uint32(/* id 1, wireType 0 =*/8).bool(message.google);
                    if (message.facebook != null && $Object.hasOwnProperty.call(message, "facebook") && message.facebook !== false)
                        writer.uint32(/* id 2, wireType 0 =*/16).bool(message.facebook);
                    if (message.discord != null && $Object.hasOwnProperty.call(message, "discord") && message.discord !== false)
                        writer.uint32(/* id 3, wireType 0 =*/24).bool(message.discord);
                    if (message.apple != null && $Object.hasOwnProperty.call(message, "apple") && message.apple !== false)
                        writer.uint32(/* id 4, wireType 0 =*/32).bool(message.apple);
                    if (message.steam != null && $Object.hasOwnProperty.call(message, "steam") && message.steam !== false)
                        writer.uint32(/* id 5, wireType 0 =*/40).bool(message.steam);
                    if (message.device != null && $Object.hasOwnProperty.call(message, "device") && message.device !== false)
                        writer.uint32(/* id 6, wireType 0 =*/48).bool(message.device);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a LinkedProviders message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.LinkedProviders & gamend.realtime.v1.LinkedProviders.$Shape} LinkedProviders
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                LinkedProviders.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.LinkedProviders(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.google = value;
                                else
                                    delete message.google;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.facebook = value;
                                else
                                    delete message.facebook;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.discord = value;
                                else
                                    delete message.discord;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.apple = value;
                                else
                                    delete message.apple;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.steam = value;
                                else
                                    delete message.steam;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.bool())
                                    message.device = value;
                                else
                                    delete message.device;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a LinkedProviders message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.LinkedProviders} LinkedProviders
                 */
                LinkedProviders.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.LinkedProviders)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.LinkedProviders: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.LinkedProviders();
                    if (object.google != null)
                        if (object.google)
                            message.google = $Boolean(object.google);
                    if (object.facebook != null)
                        if (object.facebook)
                            message.facebook = $Boolean(object.facebook);
                    if (object.discord != null)
                        if (object.discord)
                            message.discord = $Boolean(object.discord);
                    if (object.apple != null)
                        if (object.apple)
                            message.apple = $Boolean(object.apple);
                    if (object.steam != null)
                        if (object.steam)
                            message.steam = $Boolean(object.steam);
                    if (object.device != null)
                        if (object.device)
                            message.device = $Boolean(object.device);
                    return message;
                };

                /**
                 * Creates a plain object from a LinkedProviders message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @static
                 * @param {gamend.realtime.v1.LinkedProviders} message LinkedProviders
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                LinkedProviders.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.google = false;
                        object.facebook = false;
                        object.discord = false;
                        object.apple = false;
                        object.steam = false;
                        object.device = false;
                    }
                    if (message.google != null && $Object.hasOwnProperty.call(message, "google"))
                        object.google = message.google;
                    if (message.facebook != null && $Object.hasOwnProperty.call(message, "facebook"))
                        object.facebook = message.facebook;
                    if (message.discord != null && $Object.hasOwnProperty.call(message, "discord"))
                        object.discord = message.discord;
                    if (message.apple != null && $Object.hasOwnProperty.call(message, "apple"))
                        object.apple = message.apple;
                    if (message.steam != null && $Object.hasOwnProperty.call(message, "steam"))
                        object.steam = message.steam;
                    if (message.device != null && $Object.hasOwnProperty.call(message, "device"))
                        object.device = message.device;
                    return object;
                };

                /**
                 * Converts this LinkedProviders to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                LinkedProviders.prototype.toJSON = function() {
                    return LinkedProviders.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for LinkedProviders
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.LinkedProviders
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                LinkedProviders.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.LinkedProviders";
                };

                return LinkedProviders;
            })();

            v1.User = (function() {

                /**
                 * Properties of a User.
                 * @typedef {Object} gamend.realtime.v1.User.$Properties
                 * @property {string|null} [id] User id
                 * @property {string|null} [email] User email
                 * @property {string|null} [profile_url] User profile_url
                 * @property {Uint8Array|null} [metadata_json] User metadata_json
                 * @property {string|null} [display_name] User display_name
                 * @property {string|null} [lobby_id] User lobby_id
                 * @property {string|null} [party_id] User party_id
                 * @property {boolean|null} [is_online] User is_online
                 * @property {number|Long|null} [last_seen_at_ms] User last_seen_at_ms
                 * @property {gamend.realtime.v1.LinkedProviders.$Properties|null} [linked_providers] User linked_providers
                 * @property {boolean|null} [has_password] User has_password
                 * @property {Uint8Array|null} [metadata_pb] User metadata_pb
                 * @property {string|null} [username] User username
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a User.
                 * @memberof gamend.realtime.v1
                 * @interface IUser
                 * @augments gamend.realtime.v1.User.$Properties
                 * @deprecated Use gamend.realtime.v1.User.$Properties instead.
                 */

                /**
                 * Shape of a User.
                 * @typedef {gamend.realtime.v1.User.$Properties} gamend.realtime.v1.User.$Shape
                 */

                /**
                 * Constructs a new User.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a User.
                 * @constructor
                 * @param {gamend.realtime.v1.User.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const User = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * User id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.id = null;

                /**
                 * User email.
                 * @member {string|null|undefined} email
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.email = null;

                /**
                 * User profile_url.
                 * @member {string|null|undefined} profile_url
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.profile_url = null;

                /**
                 * User metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.metadata_json = null;

                /**
                 * User display_name.
                 * @member {string|null|undefined} display_name
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.display_name = null;

                /**
                 * User lobby_id.
                 * @member {string|null|undefined} lobby_id
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.lobby_id = null;

                /**
                 * User party_id.
                 * @member {string|null|undefined} party_id
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.party_id = null;

                /**
                 * User is_online.
                 * @member {boolean|null|undefined} is_online
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.is_online = null;

                /**
                 * User last_seen_at_ms.
                 * @member {number|Long|null|undefined} last_seen_at_ms
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.last_seen_at_ms = null;

                /**
                 * User linked_providers.
                 * @member {gamend.realtime.v1.LinkedProviders.$Properties|null|undefined} linked_providers
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.linked_providers = null;

                /**
                 * User has_password.
                 * @member {boolean|null|undefined} has_password
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.has_password = null;

                /**
                 * User metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.metadata_pb = null;

                /**
                 * User username.
                 * @member {string|null|undefined} username
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 */
                User.prototype.username = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_email", {
                    get: $util.oneOfGetter($oneOfFields = ["email"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_profile_url", {
                    get: $util.oneOfGetter($oneOfFields = ["profile_url"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_display_name", {
                    get: $util.oneOfGetter($oneOfFields = ["display_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_lobby_id", {
                    get: $util.oneOfGetter($oneOfFields = ["lobby_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_party_id", {
                    get: $util.oneOfGetter($oneOfFields = ["party_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_is_online", {
                    get: $util.oneOfGetter($oneOfFields = ["is_online"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_last_seen_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["last_seen_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_linked_providers", {
                    get: $util.oneOfGetter($oneOfFields = ["linked_providers"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_has_password", {
                    get: $util.oneOfGetter($oneOfFields = ["has_password"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(User.prototype, "_username", {
                    get: $util.oneOfGetter($oneOfFields = ["username"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified User message. Does not implicitly {@link gamend.realtime.v1.User.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.User
                 * @static
                 * @param {gamend.realtime.v1.User.$Properties} message User message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                User.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.email != null && $Object.hasOwnProperty.call(message, "email"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.email);
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.profile_url);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 4, wireType 2 =*/34).bytes(message.metadata_json);
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        writer.uint32(/* id 5, wireType 2 =*/42).string(message.display_name);
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.lobby_id);
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id"))
                        writer.uint32(/* id 7, wireType 2 =*/58).string(message.party_id);
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        writer.uint32(/* id 8, wireType 0 =*/64).bool(message.is_online);
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        writer.uint32(/* id 9, wireType 0 =*/72).int64(message.last_seen_at_ms);
                    if (message.linked_providers != null && $Object.hasOwnProperty.call(message, "linked_providers"))
                        $root.gamend.realtime.v1.LinkedProviders.encode(message.linked_providers, writer.uint32(/* id 10, wireType 2 =*/82).fork(), _depth + 1).ldelim();
                    if (message.has_password != null && $Object.hasOwnProperty.call(message, "has_password"))
                        writer.uint32(/* id 11, wireType 0 =*/88).bool(message.has_password);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 12, wireType 2 =*/98).bytes(message.metadata_pb);
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        writer.uint32(/* id 13, wireType 2 =*/106).string(message.username);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a User message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.User
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.User & gamend.realtime.v1.User.$Shape} User
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                User.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.User();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.email = reader.stringVerify();
                                message._email = "email";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.profile_url = reader.stringVerify();
                                message._profile_url = "profile_url";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                message.display_name = reader.stringVerify();
                                message._display_name = "display_name";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                message.lobby_id = reader.stringVerify();
                                message._lobby_id = "lobby_id";
                                continue;
                            }
                        case 7: {
                                if (wireType !== 2)
                                    break;
                                message.party_id = reader.stringVerify();
                                message._party_id = "party_id";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                message.is_online = reader.bool();
                                message._is_online = "is_online";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 0)
                                    break;
                                message.last_seen_at_ms = reader.int64();
                                message._last_seen_at_ms = "last_seen_at_ms";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 2)
                                    break;
                                message.linked_providers = $root.gamend.realtime.v1.LinkedProviders.decode(reader, reader.uint32(), $undefined, _depth + 1, message.linked_providers);
                                message._linked_providers = "linked_providers";
                                continue;
                            }
                        case 11: {
                                if (wireType !== 0)
                                    break;
                                message.has_password = reader.bool();
                                message._has_password = "has_password";
                                continue;
                            }
                        case 12: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        case 13: {
                                if (wireType !== 2)
                                    break;
                                message.username = reader.stringVerify();
                                message._username = "username";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a User message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.User
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.User} User
                 */
                User.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.User)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.User: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.User();
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.email != null)
                        message.email = $String(object.email);
                    if (object.profile_url != null)
                        message.profile_url = $String(object.profile_url);
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.display_name != null)
                        message.display_name = $String(object.display_name);
                    if (object.lobby_id != null)
                        message.lobby_id = $String(object.lobby_id);
                    if (object.party_id != null)
                        message.party_id = $String(object.party_id);
                    if (object.is_online != null)
                        message.is_online = $Boolean(object.is_online);
                    if (object.last_seen_at_ms != null)
                        if ($util.Long)
                            message.last_seen_at_ms = $util.Long.fromValue(object.last_seen_at_ms, false);
                        else if (typeof object.last_seen_at_ms === "string")
                            message.last_seen_at_ms = $parseInt(object.last_seen_at_ms, 10);
                        else if (typeof object.last_seen_at_ms === "number")
                            message.last_seen_at_ms = object.last_seen_at_ms;
                        else if (typeof object.last_seen_at_ms === "object")
                            message.last_seen_at_ms = new $util.LongBits(object.last_seen_at_ms.low >>> 0, object.last_seen_at_ms.high >>> 0).toNumber();
                    if (object.linked_providers != null) {
                        if (!$util.isObject(object.linked_providers))
                            throw $TypeError(".gamend.realtime.v1.User.linked_providers: object expected");
                        message.linked_providers = $root.gamend.realtime.v1.LinkedProviders.fromObject(object.linked_providers, _depth + 1);
                    }
                    if (object.has_password != null)
                        message.has_password = $Boolean(object.has_password);
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    if (object.username != null)
                        message.username = $String(object.username);
                    return message;
                };

                /**
                 * Creates a plain object from a User message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.User
                 * @static
                 * @param {gamend.realtime.v1.User} message User
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                User.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.email != null && $Object.hasOwnProperty.call(message, "email"))
                        object.email = message.email;
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        object.profile_url = message.profile_url;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        object.display_name = message.display_name;
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        object.lobby_id = message.lobby_id;
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id"))
                        object.party_id = message.party_id;
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        object.is_online = message.is_online;
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.last_seen_at_ms = typeof message.last_seen_at_ms === "number" ? $BigInt(message.last_seen_at_ms) : $util.Long.fromBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.last_seen_at_ms === "number")
                            object.last_seen_at_ms = options.longs === $String ? $String(message.last_seen_at_ms) : message.last_seen_at_ms;
                        else
                            object.last_seen_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.last_seen_at_ms) : options.longs === $Number ? new $util.LongBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0).toNumber() : message.last_seen_at_ms;
                    if (message.linked_providers != null && $Object.hasOwnProperty.call(message, "linked_providers"))
                        object.linked_providers = $root.gamend.realtime.v1.LinkedProviders.toObject(message.linked_providers, options, _depth + 1);
                    if (message.has_password != null && $Object.hasOwnProperty.call(message, "has_password"))
                        object.has_password = message.has_password;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        object.username = message.username;
                    return object;
                };

                /**
                 * Converts this User to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.User
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                User.prototype.toJSON = function() {
                    return User.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for User
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.User
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                User.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.User";
                };

                return User;
            })();

            v1.FriendUpdate = (function() {

                /**
                 * Properties of a FriendUpdate.
                 * @typedef {Object} gamend.realtime.v1.FriendUpdate.$Properties
                 * @property {Object.<string,gamend.realtime.v1.User.$Properties>|null} [friends] FriendUpdate friends
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a FriendUpdate.
                 * @memberof gamend.realtime.v1
                 * @interface IFriendUpdate
                 * @augments gamend.realtime.v1.FriendUpdate.$Properties
                 * @deprecated Use gamend.realtime.v1.FriendUpdate.$Properties instead.
                 */

                /**
                 * Shape of a FriendUpdate.
                 * @typedef {gamend.realtime.v1.FriendUpdate.$Properties} gamend.realtime.v1.FriendUpdate.$Shape
                 */

                /**
                 * Constructs a new FriendUpdate.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a FriendUpdate.
                 * @constructor
                 * @param {gamend.realtime.v1.FriendUpdate.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const FriendUpdate = function (properties) {
                    this.friends = {};
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * FriendUpdate friends.
                 * @member {Object.<string,gamend.realtime.v1.User.$Properties>} friends
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @instance
                 */
                FriendUpdate.prototype.friends = $util.emptyObject;

                /**
                 * Encodes the specified FriendUpdate message. Does not implicitly {@link gamend.realtime.v1.FriendUpdate.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @static
                 * @param {gamend.realtime.v1.FriendUpdate.$Properties} message FriendUpdate message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                FriendUpdate.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.friends != null && $Object.hasOwnProperty.call(message, "friends"))
                        for (let keys = $Object.keys(message.friends), i = 0; i < keys.length; ++i) {
                            writer.uint32(/* id 1, wireType 2 =*/10).fork().uint32(/* id 1, wireType 2 =*/10).string(keys[i]);
                            $root.gamend.realtime.v1.User.encode(message.friends[keys[i]], writer.uint32(/* id 2, wireType 2 =*/18).fork(), _depth + 1).ldelim().ldelim();
                        }
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a FriendUpdate message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.FriendUpdate & gamend.realtime.v1.FriendUpdate.$Shape} FriendUpdate
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                FriendUpdate.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.FriendUpdate(), key, value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if (message.friends === $util.emptyObject)
                                    message.friends = {};
                                let end2 = reader.uint32() + reader.pos;
                                key = "";
                                value = null;
                                while (reader.pos < end2) {
                                    let tag2 = reader.tag();
                                    wireType = tag2 & 7;
                                    switch (tag2 >>>= 3) {
                                    case 1:
                                        if (wireType !== 2)
                                            break;
                                        key = reader.stringVerify();
                                        continue;
                                    case 2:
                                        if (wireType !== 2)
                                            break;
                                        value = $root.gamend.realtime.v1.User.decode(reader, reader.uint32(), $undefined, _depth + 1, value);
                                        continue;
                                    }
                                    reader.skipType(wireType, _depth, tag2);
                                }
                                if (key === "__proto__")
                                    $util.makeProp(message.friends, key);
                                message.friends[key] = value || new $root.gamend.realtime.v1.User();
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a FriendUpdate message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.FriendUpdate} FriendUpdate
                 */
                FriendUpdate.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.FriendUpdate)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.FriendUpdate: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.FriendUpdate();
                    if (object.friends) {
                        if (!$util.isObject(object.friends))
                            throw $TypeError(".gamend.realtime.v1.FriendUpdate.friends: object expected");
                        message.friends = {};
                        for (let keys = $Object.keys(object.friends), i = 0; i < keys.length; ++i) {
                            if (keys[i] === "__proto__")
                                $util.makeProp(message.friends, keys[i]);
                            if (!$util.isObject(object.friends[keys[i]]))
                                throw $TypeError(".gamend.realtime.v1.FriendUpdate.friends: object expected");
                            message.friends[keys[i]] = $root.gamend.realtime.v1.User.fromObject(object.friends[keys[i]], _depth + 1);
                        }
                    }
                    return message;
                };

                /**
                 * Creates a plain object from a FriendUpdate message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @static
                 * @param {gamend.realtime.v1.FriendUpdate} message FriendUpdate
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                FriendUpdate.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.objects || options.defaults)
                        object.friends = {};
                    let keys2;
                    if (message.friends && (keys2 = $Object.keys(message.friends)).length) {
                        object.friends = {};
                        for (let j = 0; j < keys2.length; ++j) {
                            if (keys2[j] === "__proto__")
                                $util.makeProp(object.friends, keys2[j]);
                            object.friends[keys2[j]] = $root.gamend.realtime.v1.User.toObject(message.friends[keys2[j]], options, _depth + 1);
                        }
                    }
                    return object;
                };

                /**
                 * Converts this FriendUpdate to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                FriendUpdate.prototype.toJSON = function() {
                    return FriendUpdate.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for FriendUpdate
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.FriendUpdate
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                FriendUpdate.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.FriendUpdate";
                };

                return FriendUpdate;
            })();

            v1.UserBrief = (function() {

                /**
                 * Properties of a UserBrief.
                 * @typedef {Object} gamend.realtime.v1.UserBrief.$Properties
                 * @property {string|null} [id] UserBrief id
                 * @property {string|null} [display_name] UserBrief display_name
                 * @property {string|null} [profile_url] UserBrief profile_url
                 * @property {Uint8Array|null} [metadata_json] UserBrief metadata_json
                 * @property {boolean|null} [is_online] UserBrief is_online
                 * @property {boolean|null} [is_activated] UserBrief is_activated
                 * @property {number|Long|null} [last_seen_at_ms] UserBrief last_seen_at_ms
                 * @property {Uint8Array|null} [metadata_pb] UserBrief metadata_pb
                 * @property {string|null} [username] UserBrief username
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a UserBrief.
                 * @memberof gamend.realtime.v1
                 * @interface IUserBrief
                 * @augments gamend.realtime.v1.UserBrief.$Properties
                 * @deprecated Use gamend.realtime.v1.UserBrief.$Properties instead.
                 */

                /**
                 * Shape of a UserBrief.
                 * @typedef {gamend.realtime.v1.UserBrief.$Properties} gamend.realtime.v1.UserBrief.$Shape
                 */

                /**
                 * Constructs a new UserBrief.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a UserBrief.
                 * @constructor
                 * @param {gamend.realtime.v1.UserBrief.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const UserBrief = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * UserBrief id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.id = null;

                /**
                 * UserBrief display_name.
                 * @member {string|null|undefined} display_name
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.display_name = null;

                /**
                 * UserBrief profile_url.
                 * @member {string|null|undefined} profile_url
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.profile_url = null;

                /**
                 * UserBrief metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.metadata_json = null;

                /**
                 * UserBrief is_online.
                 * @member {boolean|null|undefined} is_online
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.is_online = null;

                /**
                 * UserBrief is_activated.
                 * @member {boolean|null|undefined} is_activated
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.is_activated = null;

                /**
                 * UserBrief last_seen_at_ms.
                 * @member {number|Long|null|undefined} last_seen_at_ms
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.last_seen_at_ms = null;

                /**
                 * UserBrief metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.metadata_pb = null;

                /**
                 * UserBrief username.
                 * @member {string|null|undefined} username
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 */
                UserBrief.prototype.username = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_display_name", {
                    get: $util.oneOfGetter($oneOfFields = ["display_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_profile_url", {
                    get: $util.oneOfGetter($oneOfFields = ["profile_url"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_is_online", {
                    get: $util.oneOfGetter($oneOfFields = ["is_online"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_is_activated", {
                    get: $util.oneOfGetter($oneOfFields = ["is_activated"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_last_seen_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["last_seen_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(UserBrief.prototype, "_username", {
                    get: $util.oneOfGetter($oneOfFields = ["username"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified UserBrief message. Does not implicitly {@link gamend.realtime.v1.UserBrief.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.UserBrief
                 * @static
                 * @param {gamend.realtime.v1.UserBrief.$Properties} message UserBrief message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                UserBrief.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.display_name);
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.profile_url);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 4, wireType 2 =*/34).bytes(message.metadata_json);
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        writer.uint32(/* id 5, wireType 0 =*/40).bool(message.is_online);
                    if (message.is_activated != null && $Object.hasOwnProperty.call(message, "is_activated"))
                        writer.uint32(/* id 6, wireType 0 =*/48).bool(message.is_activated);
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        writer.uint32(/* id 7, wireType 0 =*/56).int64(message.last_seen_at_ms);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 8, wireType 2 =*/66).bytes(message.metadata_pb);
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        writer.uint32(/* id 9, wireType 2 =*/74).string(message.username);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a UserBrief message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.UserBrief
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.UserBrief & gamend.realtime.v1.UserBrief.$Shape} UserBrief
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                UserBrief.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.UserBrief();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.display_name = reader.stringVerify();
                                message._display_name = "display_name";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.profile_url = reader.stringVerify();
                                message._profile_url = "profile_url";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                message.is_online = reader.bool();
                                message._is_online = "is_online";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 0)
                                    break;
                                message.is_activated = reader.bool();
                                message._is_activated = "is_activated";
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                message.last_seen_at_ms = reader.int64();
                                message._last_seen_at_ms = "last_seen_at_ms";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 2)
                                    break;
                                message.username = reader.stringVerify();
                                message._username = "username";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a UserBrief message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.UserBrief
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.UserBrief} UserBrief
                 */
                UserBrief.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.UserBrief)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.UserBrief: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.UserBrief();
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.display_name != null)
                        message.display_name = $String(object.display_name);
                    if (object.profile_url != null)
                        message.profile_url = $String(object.profile_url);
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.is_online != null)
                        message.is_online = $Boolean(object.is_online);
                    if (object.is_activated != null)
                        message.is_activated = $Boolean(object.is_activated);
                    if (object.last_seen_at_ms != null)
                        if ($util.Long)
                            message.last_seen_at_ms = $util.Long.fromValue(object.last_seen_at_ms, false);
                        else if (typeof object.last_seen_at_ms === "string")
                            message.last_seen_at_ms = $parseInt(object.last_seen_at_ms, 10);
                        else if (typeof object.last_seen_at_ms === "number")
                            message.last_seen_at_ms = object.last_seen_at_ms;
                        else if (typeof object.last_seen_at_ms === "object")
                            message.last_seen_at_ms = new $util.LongBits(object.last_seen_at_ms.low >>> 0, object.last_seen_at_ms.high >>> 0).toNumber();
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    if (object.username != null)
                        message.username = $String(object.username);
                    return message;
                };

                /**
                 * Creates a plain object from a UserBrief message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.UserBrief
                 * @static
                 * @param {gamend.realtime.v1.UserBrief} message UserBrief
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                UserBrief.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        object.display_name = message.display_name;
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        object.profile_url = message.profile_url;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        object.is_online = message.is_online;
                    if (message.is_activated != null && $Object.hasOwnProperty.call(message, "is_activated"))
                        object.is_activated = message.is_activated;
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.last_seen_at_ms = typeof message.last_seen_at_ms === "number" ? $BigInt(message.last_seen_at_ms) : $util.Long.fromBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.last_seen_at_ms === "number")
                            object.last_seen_at_ms = options.longs === $String ? $String(message.last_seen_at_ms) : message.last_seen_at_ms;
                        else
                            object.last_seen_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.last_seen_at_ms) : options.longs === $Number ? new $util.LongBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0).toNumber() : message.last_seen_at_ms;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        object.username = message.username;
                    return object;
                };

                /**
                 * Converts this UserBrief to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.UserBrief
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                UserBrief.prototype.toJSON = function() {
                    return UserBrief.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for UserBrief
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.UserBrief
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                UserBrief.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.UserBrief";
                };

                return UserBrief;
            })();

            v1.Notification = (function() {

                /**
                 * Properties of a Notification.
                 * @typedef {Object} gamend.realtime.v1.Notification.$Properties
                 * @property {string|null} [id] Notification id
                 * @property {string|null} [sender_id] Notification sender_id
                 * @property {string|null} [sender_name] Notification sender_name
                 * @property {string|null} [recipient_id] Notification recipient_id
                 * @property {string|null} [title] Notification title
                 * @property {string|null} [content] Notification content
                 * @property {Uint8Array|null} [metadata_json] Notification metadata_json
                 * @property {number|Long|null} [inserted_at_ms] Notification inserted_at_ms
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a Notification.
                 * @memberof gamend.realtime.v1
                 * @interface INotification
                 * @augments gamend.realtime.v1.Notification.$Properties
                 * @deprecated Use gamend.realtime.v1.Notification.$Properties instead.
                 */

                /**
                 * Shape of a Notification.
                 * @typedef {gamend.realtime.v1.Notification.$Properties} gamend.realtime.v1.Notification.$Shape
                 */

                /**
                 * Constructs a new Notification.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a Notification.
                 * @constructor
                 * @param {gamend.realtime.v1.Notification.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const Notification = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * Notification id.
                 * @member {string} id
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.id = "";

                /**
                 * Notification sender_id.
                 * @member {string} sender_id
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.sender_id = "";

                /**
                 * Notification sender_name.
                 * @member {string} sender_name
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.sender_name = "";

                /**
                 * Notification recipient_id.
                 * @member {string} recipient_id
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.recipient_id = "";

                /**
                 * Notification title.
                 * @member {string} title
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.title = "";

                /**
                 * Notification content.
                 * @member {string} content
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.content = "";

                /**
                 * Notification metadata_json.
                 * @member {Uint8Array} metadata_json
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.metadata_json = $util.newBuffer([]);

                /**
                 * Notification inserted_at_ms.
                 * @member {number|Long} inserted_at_ms
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 */
                Notification.prototype.inserted_at_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                /**
                 * Encodes the specified Notification message. Does not implicitly {@link gamend.realtime.v1.Notification.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.Notification
                 * @static
                 * @param {gamend.realtime.v1.Notification.$Properties} message Notification message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                Notification.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.sender_id != null && $Object.hasOwnProperty.call(message, "sender_id") && message.sender_id !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.sender_id);
                    if (message.sender_name != null && $Object.hasOwnProperty.call(message, "sender_name") && message.sender_name !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.sender_name);
                    if (message.recipient_id != null && $Object.hasOwnProperty.call(message, "recipient_id") && message.recipient_id !== "")
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.recipient_id);
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title") && message.title !== "")
                        writer.uint32(/* id 5, wireType 2 =*/42).string(message.title);
                    if (message.content != null && $Object.hasOwnProperty.call(message, "content") && message.content !== "")
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.content);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json") && message.metadata_json.length)
                        writer.uint32(/* id 7, wireType 2 =*/58).bytes(message.metadata_json);
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms") && (typeof message.inserted_at_ms === "object" ? message.inserted_at_ms.low || message.inserted_at_ms.high : message.inserted_at_ms !== 0))
                        writer.uint32(/* id 8, wireType 0 =*/64).int64(message.inserted_at_ms);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a Notification message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.Notification
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.Notification & gamend.realtime.v1.Notification.$Shape} Notification
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                Notification.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.Notification(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.sender_id = value;
                                else
                                    delete message.sender_id;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.sender_name = value;
                                else
                                    delete message.sender_name;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.recipient_id = value;
                                else
                                    delete message.recipient_id;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.title = value;
                                else
                                    delete message.title;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.content = value;
                                else
                                    delete message.content;
                                continue;
                            }
                        case 7: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.bytes()).length)
                                    message.metadata_json = value;
                                else
                                    delete message.metadata_json;
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.inserted_at_ms = value;
                                else
                                    delete message.inserted_at_ms;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a Notification message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.Notification
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.Notification} Notification
                 */
                Notification.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.Notification)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.Notification: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.Notification();
                    if (object.id != null)
                        if (typeof object.id !== "string" || object.id.length)
                            message.id = $String(object.id);
                    if (object.sender_id != null)
                        if (typeof object.sender_id !== "string" || object.sender_id.length)
                            message.sender_id = $String(object.sender_id);
                    if (object.sender_name != null)
                        if (typeof object.sender_name !== "string" || object.sender_name.length)
                            message.sender_name = $String(object.sender_name);
                    if (object.recipient_id != null)
                        if (typeof object.recipient_id !== "string" || object.recipient_id.length)
                            message.recipient_id = $String(object.recipient_id);
                    if (object.title != null)
                        if (typeof object.title !== "string" || object.title.length)
                            message.title = $String(object.title);
                    if (object.content != null)
                        if (typeof object.content !== "string" || object.content.length)
                            message.content = $String(object.content);
                    if (object.metadata_json != null)
                        if (object.metadata_json.length)
                            if (typeof object.metadata_json === "string")
                                $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                            else if (object.metadata_json.length >= 0)
                                message.metadata_json = object.metadata_json;
                    if (object.inserted_at_ms != null)
                        if (typeof object.inserted_at_ms === "object" ? object.inserted_at_ms.low || object.inserted_at_ms.high : $Number(object.inserted_at_ms) !== 0)
                            if ($util.Long)
                                message.inserted_at_ms = $util.Long.fromValue(object.inserted_at_ms, false);
                            else if (typeof object.inserted_at_ms === "string")
                                message.inserted_at_ms = $parseInt(object.inserted_at_ms, 10);
                            else if (typeof object.inserted_at_ms === "number")
                                message.inserted_at_ms = object.inserted_at_ms;
                            else if (typeof object.inserted_at_ms === "object")
                                message.inserted_at_ms = new $util.LongBits(object.inserted_at_ms.low >>> 0, object.inserted_at_ms.high >>> 0).toNumber();
                    return message;
                };

                /**
                 * Creates a plain object from a Notification message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.Notification
                 * @static
                 * @param {gamend.realtime.v1.Notification} message Notification
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                Notification.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.id = "";
                        object.sender_id = "";
                        object.sender_name = "";
                        object.recipient_id = "";
                        object.title = "";
                        object.content = "";
                        if (options.bytes === $String)
                            object.metadata_json = "";
                        else {
                            object.metadata_json = [];
                            if (options.bytes !== $Array)
                                object.metadata_json = $util.newBuffer(object.metadata_json);
                        }
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.inserted_at_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.inserted_at_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.sender_id != null && $Object.hasOwnProperty.call(message, "sender_id"))
                        object.sender_id = message.sender_id;
                    if (message.sender_name != null && $Object.hasOwnProperty.call(message, "sender_name"))
                        object.sender_name = message.sender_name;
                    if (message.recipient_id != null && $Object.hasOwnProperty.call(message, "recipient_id"))
                        object.recipient_id = message.recipient_id;
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title"))
                        object.title = message.title;
                    if (message.content != null && $Object.hasOwnProperty.call(message, "content"))
                        object.content = message.content;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.inserted_at_ms = typeof message.inserted_at_ms === "number" ? $BigInt(message.inserted_at_ms) : $util.Long.fromBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.inserted_at_ms === "number")
                            object.inserted_at_ms = options.longs === $String ? $String(message.inserted_at_ms) : message.inserted_at_ms;
                        else
                            object.inserted_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.inserted_at_ms) : options.longs === $Number ? new $util.LongBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0).toNumber() : message.inserted_at_ms;
                    return object;
                };

                /**
                 * Converts this Notification to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.Notification
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                Notification.prototype.toJSON = function() {
                    return Notification.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for Notification
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.Notification
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                Notification.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.Notification";
                };

                return Notification;
            })();

            v1.ChatMessage = (function() {

                /**
                 * Properties of a ChatMessage.
                 * @typedef {Object} gamend.realtime.v1.ChatMessage.$Properties
                 * @property {string|null} [id] ChatMessage id
                 * @property {string|null} [content] ChatMessage content
                 * @property {Uint8Array|null} [metadata_json] ChatMessage metadata_json
                 * @property {string|null} [sender_id] ChatMessage sender_id
                 * @property {string|null} [sender_name] ChatMessage sender_name
                 * @property {string|null} [chat_type] ChatMessage chat_type
                 * @property {string|null} [chat_ref_id] ChatMessage chat_ref_id
                 * @property {number|Long|null} [inserted_at_ms] ChatMessage inserted_at_ms
                 * @property {number|Long|null} [updated_at_ms] ChatMessage updated_at_ms
                 * @property {string|null} [sender_email] ChatMessage sender_email
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a ChatMessage.
                 * @memberof gamend.realtime.v1
                 * @interface IChatMessage
                 * @augments gamend.realtime.v1.ChatMessage.$Properties
                 * @deprecated Use gamend.realtime.v1.ChatMessage.$Properties instead.
                 */

                /**
                 * Shape of a ChatMessage.
                 * @typedef {gamend.realtime.v1.ChatMessage.$Properties} gamend.realtime.v1.ChatMessage.$Shape
                 */

                /**
                 * Constructs a new ChatMessage.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a ChatMessage.
                 * @constructor
                 * @param {gamend.realtime.v1.ChatMessage.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const ChatMessage = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * ChatMessage id.
                 * @member {string} id
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.id = "";

                /**
                 * ChatMessage content.
                 * @member {string} content
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.content = "";

                /**
                 * ChatMessage metadata_json.
                 * @member {Uint8Array} metadata_json
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.metadata_json = $util.newBuffer([]);

                /**
                 * ChatMessage sender_id.
                 * @member {string} sender_id
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.sender_id = "";

                /**
                 * ChatMessage sender_name.
                 * @member {string} sender_name
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.sender_name = "";

                /**
                 * ChatMessage chat_type.
                 * @member {string} chat_type
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.chat_type = "";

                /**
                 * ChatMessage chat_ref_id.
                 * @member {string} chat_ref_id
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.chat_ref_id = "";

                /**
                 * ChatMessage inserted_at_ms.
                 * @member {number|Long} inserted_at_ms
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.inserted_at_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                /**
                 * ChatMessage updated_at_ms.
                 * @member {number|Long|null|undefined} updated_at_ms
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.updated_at_ms = null;

                /**
                 * ChatMessage sender_email.
                 * @member {string|null|undefined} sender_email
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 */
                ChatMessage.prototype.sender_email = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(ChatMessage.prototype, "_updated_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["updated_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(ChatMessage.prototype, "_sender_email", {
                    get: $util.oneOfGetter($oneOfFields = ["sender_email"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified ChatMessage message. Does not implicitly {@link gamend.realtime.v1.ChatMessage.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @static
                 * @param {gamend.realtime.v1.ChatMessage.$Properties} message ChatMessage message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                ChatMessage.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.content != null && $Object.hasOwnProperty.call(message, "content") && message.content !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.content);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json") && message.metadata_json.length)
                        writer.uint32(/* id 3, wireType 2 =*/26).bytes(message.metadata_json);
                    if (message.sender_id != null && $Object.hasOwnProperty.call(message, "sender_id") && message.sender_id !== "")
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.sender_id);
                    if (message.sender_name != null && $Object.hasOwnProperty.call(message, "sender_name") && message.sender_name !== "")
                        writer.uint32(/* id 5, wireType 2 =*/42).string(message.sender_name);
                    if (message.chat_type != null && $Object.hasOwnProperty.call(message, "chat_type") && message.chat_type !== "")
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.chat_type);
                    if (message.chat_ref_id != null && $Object.hasOwnProperty.call(message, "chat_ref_id") && message.chat_ref_id !== "")
                        writer.uint32(/* id 7, wireType 2 =*/58).string(message.chat_ref_id);
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms") && (typeof message.inserted_at_ms === "object" ? message.inserted_at_ms.low || message.inserted_at_ms.high : message.inserted_at_ms !== 0))
                        writer.uint32(/* id 8, wireType 0 =*/64).int64(message.inserted_at_ms);
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        writer.uint32(/* id 9, wireType 0 =*/72).int64(message.updated_at_ms);
                    if (message.sender_email != null && $Object.hasOwnProperty.call(message, "sender_email"))
                        writer.uint32(/* id 10, wireType 2 =*/82).string(message.sender_email);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a ChatMessage message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.ChatMessage & gamend.realtime.v1.ChatMessage.$Shape} ChatMessage
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                ChatMessage.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.ChatMessage(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.content = value;
                                else
                                    delete message.content;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.bytes()).length)
                                    message.metadata_json = value;
                                else
                                    delete message.metadata_json;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.sender_id = value;
                                else
                                    delete message.sender_id;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.sender_name = value;
                                else
                                    delete message.sender_name;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.chat_type = value;
                                else
                                    delete message.chat_type;
                                continue;
                            }
                        case 7: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.chat_ref_id = value;
                                else
                                    delete message.chat_ref_id;
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.inserted_at_ms = value;
                                else
                                    delete message.inserted_at_ms;
                                continue;
                            }
                        case 9: {
                                if (wireType !== 0)
                                    break;
                                message.updated_at_ms = reader.int64();
                                message._updated_at_ms = "updated_at_ms";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 2)
                                    break;
                                message.sender_email = reader.stringVerify();
                                message._sender_email = "sender_email";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a ChatMessage message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.ChatMessage} ChatMessage
                 */
                ChatMessage.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.ChatMessage)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.ChatMessage: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.ChatMessage();
                    if (object.id != null)
                        if (typeof object.id !== "string" || object.id.length)
                            message.id = $String(object.id);
                    if (object.content != null)
                        if (typeof object.content !== "string" || object.content.length)
                            message.content = $String(object.content);
                    if (object.metadata_json != null)
                        if (object.metadata_json.length)
                            if (typeof object.metadata_json === "string")
                                $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                            else if (object.metadata_json.length >= 0)
                                message.metadata_json = object.metadata_json;
                    if (object.sender_id != null)
                        if (typeof object.sender_id !== "string" || object.sender_id.length)
                            message.sender_id = $String(object.sender_id);
                    if (object.sender_name != null)
                        if (typeof object.sender_name !== "string" || object.sender_name.length)
                            message.sender_name = $String(object.sender_name);
                    if (object.chat_type != null)
                        if (typeof object.chat_type !== "string" || object.chat_type.length)
                            message.chat_type = $String(object.chat_type);
                    if (object.chat_ref_id != null)
                        if (typeof object.chat_ref_id !== "string" || object.chat_ref_id.length)
                            message.chat_ref_id = $String(object.chat_ref_id);
                    if (object.inserted_at_ms != null)
                        if (typeof object.inserted_at_ms === "object" ? object.inserted_at_ms.low || object.inserted_at_ms.high : $Number(object.inserted_at_ms) !== 0)
                            if ($util.Long)
                                message.inserted_at_ms = $util.Long.fromValue(object.inserted_at_ms, false);
                            else if (typeof object.inserted_at_ms === "string")
                                message.inserted_at_ms = $parseInt(object.inserted_at_ms, 10);
                            else if (typeof object.inserted_at_ms === "number")
                                message.inserted_at_ms = object.inserted_at_ms;
                            else if (typeof object.inserted_at_ms === "object")
                                message.inserted_at_ms = new $util.LongBits(object.inserted_at_ms.low >>> 0, object.inserted_at_ms.high >>> 0).toNumber();
                    if (object.updated_at_ms != null)
                        if ($util.Long)
                            message.updated_at_ms = $util.Long.fromValue(object.updated_at_ms, false);
                        else if (typeof object.updated_at_ms === "string")
                            message.updated_at_ms = $parseInt(object.updated_at_ms, 10);
                        else if (typeof object.updated_at_ms === "number")
                            message.updated_at_ms = object.updated_at_ms;
                        else if (typeof object.updated_at_ms === "object")
                            message.updated_at_ms = new $util.LongBits(object.updated_at_ms.low >>> 0, object.updated_at_ms.high >>> 0).toNumber();
                    if (object.sender_email != null)
                        message.sender_email = $String(object.sender_email);
                    return message;
                };

                /**
                 * Creates a plain object from a ChatMessage message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @static
                 * @param {gamend.realtime.v1.ChatMessage} message ChatMessage
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                ChatMessage.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.id = "";
                        object.content = "";
                        if (options.bytes === $String)
                            object.metadata_json = "";
                        else {
                            object.metadata_json = [];
                            if (options.bytes !== $Array)
                                object.metadata_json = $util.newBuffer(object.metadata_json);
                        }
                        object.sender_id = "";
                        object.sender_name = "";
                        object.chat_type = "";
                        object.chat_ref_id = "";
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.inserted_at_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.inserted_at_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.content != null && $Object.hasOwnProperty.call(message, "content"))
                        object.content = message.content;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.sender_id != null && $Object.hasOwnProperty.call(message, "sender_id"))
                        object.sender_id = message.sender_id;
                    if (message.sender_name != null && $Object.hasOwnProperty.call(message, "sender_name"))
                        object.sender_name = message.sender_name;
                    if (message.chat_type != null && $Object.hasOwnProperty.call(message, "chat_type"))
                        object.chat_type = message.chat_type;
                    if (message.chat_ref_id != null && $Object.hasOwnProperty.call(message, "chat_ref_id"))
                        object.chat_ref_id = message.chat_ref_id;
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.inserted_at_ms = typeof message.inserted_at_ms === "number" ? $BigInt(message.inserted_at_ms) : $util.Long.fromBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.inserted_at_ms === "number")
                            object.inserted_at_ms = options.longs === $String ? $String(message.inserted_at_ms) : message.inserted_at_ms;
                        else
                            object.inserted_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.inserted_at_ms) : options.longs === $Number ? new $util.LongBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0).toNumber() : message.inserted_at_ms;
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.updated_at_ms = typeof message.updated_at_ms === "number" ? $BigInt(message.updated_at_ms) : $util.Long.fromBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.updated_at_ms === "number")
                            object.updated_at_ms = options.longs === $String ? $String(message.updated_at_ms) : message.updated_at_ms;
                        else
                            object.updated_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.updated_at_ms) : options.longs === $Number ? new $util.LongBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0).toNumber() : message.updated_at_ms;
                    if (message.sender_email != null && $Object.hasOwnProperty.call(message, "sender_email"))
                        object.sender_email = message.sender_email;
                    return object;
                };

                /**
                 * Converts this ChatMessage to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                ChatMessage.prototype.toJSON = function() {
                    return ChatMessage.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for ChatMessage
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.ChatMessage
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                ChatMessage.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.ChatMessage";
                };

                return ChatMessage;
            })();

            v1.QuestProgress = (function() {

                /**
                 * Properties of a QuestProgress.
                 * @typedef {Object} gamend.realtime.v1.QuestProgress.$Properties
                 * @property {string|null} [id] QuestProgress id
                 * @property {string|null} [user_id] QuestProgress user_id
                 * @property {string|null} [quest_key] QuestProgress quest_key
                 * @property {string|null} [period_key] QuestProgress period_key
                 * @property {Object.<string,number|Long>|null} [objective_progress] QuestProgress objective_progress
                 * @property {string|null} [status] QuestProgress status
                 * @property {number|Long|null} [completed_at_ms] QuestProgress completed_at_ms
                 * @property {number|Long|null} [claimed_at_ms] QuestProgress claimed_at_ms
                 * @property {Uint8Array|null} [metadata_json] QuestProgress metadata_json
                 * @property {number|Long|null} [inserted_at_ms] QuestProgress inserted_at_ms
                 * @property {number|Long|null} [updated_at_ms] QuestProgress updated_at_ms
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a QuestProgress.
                 * @memberof gamend.realtime.v1
                 * @interface IQuestProgress
                 * @augments gamend.realtime.v1.QuestProgress.$Properties
                 * @deprecated Use gamend.realtime.v1.QuestProgress.$Properties instead.
                 */

                /**
                 * Shape of a QuestProgress.
                 * @typedef {gamend.realtime.v1.QuestProgress.$Properties} gamend.realtime.v1.QuestProgress.$Shape
                 */

                /**
                 * Constructs a new QuestProgress.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a QuestProgress.
                 * @constructor
                 * @param {gamend.realtime.v1.QuestProgress.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const QuestProgress = function (properties) {
                    this.objective_progress = {};
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * QuestProgress id.
                 * @member {string} id
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.id = "";

                /**
                 * QuestProgress user_id.
                 * @member {string} user_id
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.user_id = "";

                /**
                 * QuestProgress quest_key.
                 * @member {string} quest_key
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.quest_key = "";

                /**
                 * QuestProgress period_key.
                 * @member {string} period_key
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.period_key = "";

                /**
                 * QuestProgress objective_progress.
                 * @member {Object.<string,number|Long>} objective_progress
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.objective_progress = $util.emptyObject;

                /**
                 * QuestProgress status.
                 * @member {string} status
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.status = "";

                /**
                 * QuestProgress completed_at_ms.
                 * @member {number|Long|null|undefined} completed_at_ms
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.completed_at_ms = null;

                /**
                 * QuestProgress claimed_at_ms.
                 * @member {number|Long|null|undefined} claimed_at_ms
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.claimed_at_ms = null;

                /**
                 * QuestProgress metadata_json.
                 * @member {Uint8Array} metadata_json
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.metadata_json = $util.newBuffer([]);

                /**
                 * QuestProgress inserted_at_ms.
                 * @member {number|Long} inserted_at_ms
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.inserted_at_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                /**
                 * QuestProgress updated_at_ms.
                 * @member {number|Long} updated_at_ms
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 */
                QuestProgress.prototype.updated_at_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(QuestProgress.prototype, "_completed_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["completed_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(QuestProgress.prototype, "_claimed_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["claimed_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified QuestProgress message. Does not implicitly {@link gamend.realtime.v1.QuestProgress.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @static
                 * @param {gamend.realtime.v1.QuestProgress.$Properties} message QuestProgress message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                QuestProgress.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id") && message.user_id !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.user_id);
                    if (message.quest_key != null && $Object.hasOwnProperty.call(message, "quest_key") && message.quest_key !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.quest_key);
                    if (message.period_key != null && $Object.hasOwnProperty.call(message, "period_key") && message.period_key !== "")
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.period_key);
                    if (message.objective_progress != null && $Object.hasOwnProperty.call(message, "objective_progress"))
                        for (let keys = $Object.keys(message.objective_progress), i = 0; i < keys.length; ++i)
                            writer.uint32(/* id 5, wireType 2 =*/42).fork().uint32(/* id 1, wireType 2 =*/10).string(keys[i]).uint32(/* id 2, wireType 0 =*/16).int64(message.objective_progress[keys[i]]).ldelim();
                    if (message.status != null && $Object.hasOwnProperty.call(message, "status") && message.status !== "")
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.status);
                    if (message.completed_at_ms != null && $Object.hasOwnProperty.call(message, "completed_at_ms"))
                        writer.uint32(/* id 7, wireType 0 =*/56).int64(message.completed_at_ms);
                    if (message.claimed_at_ms != null && $Object.hasOwnProperty.call(message, "claimed_at_ms"))
                        writer.uint32(/* id 8, wireType 0 =*/64).int64(message.claimed_at_ms);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json") && message.metadata_json.length)
                        writer.uint32(/* id 9, wireType 2 =*/74).bytes(message.metadata_json);
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms") && (typeof message.inserted_at_ms === "object" ? message.inserted_at_ms.low || message.inserted_at_ms.high : message.inserted_at_ms !== 0))
                        writer.uint32(/* id 10, wireType 0 =*/80).int64(message.inserted_at_ms);
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms") && (typeof message.updated_at_ms === "object" ? message.updated_at_ms.low || message.updated_at_ms.high : message.updated_at_ms !== 0))
                        writer.uint32(/* id 11, wireType 0 =*/88).int64(message.updated_at_ms);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a QuestProgress message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.QuestProgress & gamend.realtime.v1.QuestProgress.$Shape} QuestProgress
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                QuestProgress.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.QuestProgress(), key, value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.user_id = value;
                                else
                                    delete message.user_id;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.quest_key = value;
                                else
                                    delete message.quest_key;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.period_key = value;
                                else
                                    delete message.period_key;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                if (message.objective_progress === $util.emptyObject)
                                    message.objective_progress = {};
                                let end2 = reader.uint32() + reader.pos;
                                key = "";
                                value = $util.Long ? $util.Long.fromNumber(0, false) : 0;
                                while (reader.pos < end2) {
                                    let tag2 = reader.tag();
                                    wireType = tag2 & 7;
                                    switch (tag2 >>>= 3) {
                                    case 1:
                                        if (wireType !== 2)
                                            break;
                                        key = reader.stringVerify();
                                        continue;
                                    case 2:
                                        if (wireType !== 0)
                                            break;
                                        value = reader.int64();
                                        continue;
                                    }
                                    reader.skipType(wireType, _depth, tag2);
                                }
                                if (key === "__proto__")
                                    $util.makeProp(message.objective_progress, key);
                                message.objective_progress[key] = value;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.status = value;
                                else
                                    delete message.status;
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                message.completed_at_ms = reader.int64();
                                message._completed_at_ms = "completed_at_ms";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                message.claimed_at_ms = reader.int64();
                                message._claimed_at_ms = "claimed_at_ms";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.bytes()).length)
                                    message.metadata_json = value;
                                else
                                    delete message.metadata_json;
                                continue;
                            }
                        case 10: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.inserted_at_ms = value;
                                else
                                    delete message.inserted_at_ms;
                                continue;
                            }
                        case 11: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.updated_at_ms = value;
                                else
                                    delete message.updated_at_ms;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a QuestProgress message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.QuestProgress} QuestProgress
                 */
                QuestProgress.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.QuestProgress)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.QuestProgress: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.QuestProgress();
                    if (object.id != null)
                        if (typeof object.id !== "string" || object.id.length)
                            message.id = $String(object.id);
                    if (object.user_id != null)
                        if (typeof object.user_id !== "string" || object.user_id.length)
                            message.user_id = $String(object.user_id);
                    if (object.quest_key != null)
                        if (typeof object.quest_key !== "string" || object.quest_key.length)
                            message.quest_key = $String(object.quest_key);
                    if (object.period_key != null)
                        if (typeof object.period_key !== "string" || object.period_key.length)
                            message.period_key = $String(object.period_key);
                    if (object.objective_progress) {
                        if (!$util.isObject(object.objective_progress))
                            throw $TypeError(".gamend.realtime.v1.QuestProgress.objective_progress: object expected");
                        message.objective_progress = {};
                        for (let keys = $Object.keys(object.objective_progress), i = 0; i < keys.length; ++i) {
                            if (keys[i] === "__proto__")
                                $util.makeProp(message.objective_progress, keys[i]);
                            if ($util.Long)
                                message.objective_progress[keys[i]] = $util.Long.fromValue(object.objective_progress[keys[i]], false);
                            else if (typeof object.objective_progress[keys[i]] === "string")
                                message.objective_progress[keys[i]] = $parseInt(object.objective_progress[keys[i]], 10);
                            else if (typeof object.objective_progress[keys[i]] === "number")
                                message.objective_progress[keys[i]] = object.objective_progress[keys[i]];
                            else if (typeof object.objective_progress[keys[i]] === "object")
                                message.objective_progress[keys[i]] = new $util.LongBits(object.objective_progress[keys[i]].low >>> 0, object.objective_progress[keys[i]].high >>> 0).toNumber();
                        }
                    }
                    if (object.status != null)
                        if (typeof object.status !== "string" || object.status.length)
                            message.status = $String(object.status);
                    if (object.completed_at_ms != null)
                        if ($util.Long)
                            message.completed_at_ms = $util.Long.fromValue(object.completed_at_ms, false);
                        else if (typeof object.completed_at_ms === "string")
                            message.completed_at_ms = $parseInt(object.completed_at_ms, 10);
                        else if (typeof object.completed_at_ms === "number")
                            message.completed_at_ms = object.completed_at_ms;
                        else if (typeof object.completed_at_ms === "object")
                            message.completed_at_ms = new $util.LongBits(object.completed_at_ms.low >>> 0, object.completed_at_ms.high >>> 0).toNumber();
                    if (object.claimed_at_ms != null)
                        if ($util.Long)
                            message.claimed_at_ms = $util.Long.fromValue(object.claimed_at_ms, false);
                        else if (typeof object.claimed_at_ms === "string")
                            message.claimed_at_ms = $parseInt(object.claimed_at_ms, 10);
                        else if (typeof object.claimed_at_ms === "number")
                            message.claimed_at_ms = object.claimed_at_ms;
                        else if (typeof object.claimed_at_ms === "object")
                            message.claimed_at_ms = new $util.LongBits(object.claimed_at_ms.low >>> 0, object.claimed_at_ms.high >>> 0).toNumber();
                    if (object.metadata_json != null)
                        if (object.metadata_json.length)
                            if (typeof object.metadata_json === "string")
                                $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                            else if (object.metadata_json.length >= 0)
                                message.metadata_json = object.metadata_json;
                    if (object.inserted_at_ms != null)
                        if (typeof object.inserted_at_ms === "object" ? object.inserted_at_ms.low || object.inserted_at_ms.high : $Number(object.inserted_at_ms) !== 0)
                            if ($util.Long)
                                message.inserted_at_ms = $util.Long.fromValue(object.inserted_at_ms, false);
                            else if (typeof object.inserted_at_ms === "string")
                                message.inserted_at_ms = $parseInt(object.inserted_at_ms, 10);
                            else if (typeof object.inserted_at_ms === "number")
                                message.inserted_at_ms = object.inserted_at_ms;
                            else if (typeof object.inserted_at_ms === "object")
                                message.inserted_at_ms = new $util.LongBits(object.inserted_at_ms.low >>> 0, object.inserted_at_ms.high >>> 0).toNumber();
                    if (object.updated_at_ms != null)
                        if (typeof object.updated_at_ms === "object" ? object.updated_at_ms.low || object.updated_at_ms.high : $Number(object.updated_at_ms) !== 0)
                            if ($util.Long)
                                message.updated_at_ms = $util.Long.fromValue(object.updated_at_ms, false);
                            else if (typeof object.updated_at_ms === "string")
                                message.updated_at_ms = $parseInt(object.updated_at_ms, 10);
                            else if (typeof object.updated_at_ms === "number")
                                message.updated_at_ms = object.updated_at_ms;
                            else if (typeof object.updated_at_ms === "object")
                                message.updated_at_ms = new $util.LongBits(object.updated_at_ms.low >>> 0, object.updated_at_ms.high >>> 0).toNumber();
                    return message;
                };

                /**
                 * Creates a plain object from a QuestProgress message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @static
                 * @param {gamend.realtime.v1.QuestProgress} message QuestProgress
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                QuestProgress.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.objects || options.defaults)
                        object.objective_progress = {};
                    if (options.defaults) {
                        object.id = "";
                        object.user_id = "";
                        object.quest_key = "";
                        object.period_key = "";
                        object.status = "";
                        if (options.bytes === $String)
                            object.metadata_json = "";
                        else {
                            object.metadata_json = [];
                            if (options.bytes !== $Array)
                                object.metadata_json = $util.newBuffer(object.metadata_json);
                        }
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.inserted_at_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.inserted_at_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.updated_at_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.updated_at_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        object.user_id = message.user_id;
                    if (message.quest_key != null && $Object.hasOwnProperty.call(message, "quest_key"))
                        object.quest_key = message.quest_key;
                    if (message.period_key != null && $Object.hasOwnProperty.call(message, "period_key"))
                        object.period_key = message.period_key;
                    let keys2;
                    if (message.objective_progress && (keys2 = $Object.keys(message.objective_progress)).length) {
                        object.objective_progress = {};
                        for (let j = 0; j < keys2.length; ++j) {
                            if (keys2[j] === "__proto__")
                                $util.makeProp(object.objective_progress, keys2[j]);
                            if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                                object.objective_progress[keys2[j]] = typeof message.objective_progress[keys2[j]] === "number" ? $BigInt(message.objective_progress[keys2[j]]) : $util.Long.fromBits(message.objective_progress[keys2[j]].low >>> 0, message.objective_progress[keys2[j]].high >>> 0, false).toBigInt();
                            else if (typeof message.objective_progress[keys2[j]] === "number")
                                object.objective_progress[keys2[j]] = options.longs === $String ? $String(message.objective_progress[keys2[j]]) : message.objective_progress[keys2[j]];
                            else
                                object.objective_progress[keys2[j]] = options.longs === $String ? $util.Long.prototype.toString.call(message.objective_progress[keys2[j]]) : options.longs === $Number ? new $util.LongBits(message.objective_progress[keys2[j]].low >>> 0, message.objective_progress[keys2[j]].high >>> 0).toNumber() : message.objective_progress[keys2[j]];
                        }
                    }
                    if (message.status != null && $Object.hasOwnProperty.call(message, "status"))
                        object.status = message.status;
                    if (message.completed_at_ms != null && $Object.hasOwnProperty.call(message, "completed_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.completed_at_ms = typeof message.completed_at_ms === "number" ? $BigInt(message.completed_at_ms) : $util.Long.fromBits(message.completed_at_ms.low >>> 0, message.completed_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.completed_at_ms === "number")
                            object.completed_at_ms = options.longs === $String ? $String(message.completed_at_ms) : message.completed_at_ms;
                        else
                            object.completed_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.completed_at_ms) : options.longs === $Number ? new $util.LongBits(message.completed_at_ms.low >>> 0, message.completed_at_ms.high >>> 0).toNumber() : message.completed_at_ms;
                    if (message.claimed_at_ms != null && $Object.hasOwnProperty.call(message, "claimed_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.claimed_at_ms = typeof message.claimed_at_ms === "number" ? $BigInt(message.claimed_at_ms) : $util.Long.fromBits(message.claimed_at_ms.low >>> 0, message.claimed_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.claimed_at_ms === "number")
                            object.claimed_at_ms = options.longs === $String ? $String(message.claimed_at_ms) : message.claimed_at_ms;
                        else
                            object.claimed_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.claimed_at_ms) : options.longs === $Number ? new $util.LongBits(message.claimed_at_ms.low >>> 0, message.claimed_at_ms.high >>> 0).toNumber() : message.claimed_at_ms;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.inserted_at_ms = typeof message.inserted_at_ms === "number" ? $BigInt(message.inserted_at_ms) : $util.Long.fromBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.inserted_at_ms === "number")
                            object.inserted_at_ms = options.longs === $String ? $String(message.inserted_at_ms) : message.inserted_at_ms;
                        else
                            object.inserted_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.inserted_at_ms) : options.longs === $Number ? new $util.LongBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0).toNumber() : message.inserted_at_ms;
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.updated_at_ms = typeof message.updated_at_ms === "number" ? $BigInt(message.updated_at_ms) : $util.Long.fromBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.updated_at_ms === "number")
                            object.updated_at_ms = options.longs === $String ? $String(message.updated_at_ms) : message.updated_at_ms;
                        else
                            object.updated_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.updated_at_ms) : options.longs === $Number ? new $util.LongBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0).toNumber() : message.updated_at_ms;
                    return object;
                };

                /**
                 * Converts this QuestProgress to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                QuestProgress.prototype.toJSON = function() {
                    return QuestProgress.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for QuestProgress
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.QuestProgress
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                QuestProgress.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.QuestProgress";
                };

                return QuestProgress;
            })();

            v1.Lobby = (function() {

                /**
                 * Properties of a Lobby.
                 * @typedef {Object} gamend.realtime.v1.Lobby.$Properties
                 * @property {string|null} [id] Lobby id
                 * @property {string|null} [title] Lobby title
                 * @property {string|null} [host_id] Lobby host_id
                 * @property {string|null} [host_name] Lobby host_name
                 * @property {boolean|null} [hostless] Lobby hostless
                 * @property {number|null} [max_users] Lobby max_users
                 * @property {boolean|null} [is_hidden] Lobby is_hidden
                 * @property {boolean|null} [is_locked] Lobby is_locked
                 * @property {Uint8Array|null} [metadata_json] Lobby metadata_json
                 * @property {boolean|null} [is_passworded] Lobby is_passworded
                 * @property {number|null} [slowdown] Lobby slowdown
                 * @property {number|null} [spectator_count] Lobby spectator_count
                 * @property {Array.<gamend.realtime.v1.UserBrief.$Properties>|null} [members] Lobby members
                 * @property {boolean|null} [has_members] Lobby has_members
                 * @property {Uint8Array|null} [metadata_pb] Lobby metadata_pb
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a Lobby.
                 * @memberof gamend.realtime.v1
                 * @interface ILobby
                 * @augments gamend.realtime.v1.Lobby.$Properties
                 * @deprecated Use gamend.realtime.v1.Lobby.$Properties instead.
                 */

                /**
                 * Shape of a Lobby.
                 * @typedef {gamend.realtime.v1.Lobby.$Properties} gamend.realtime.v1.Lobby.$Shape
                 */

                /**
                 * Constructs a new Lobby.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a Lobby.
                 * @constructor
                 * @param {gamend.realtime.v1.Lobby.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const Lobby = function (properties) {
                    this.members = [];
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * Lobby id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.id = null;

                /**
                 * Lobby title.
                 * @member {string|null|undefined} title
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.title = null;

                /**
                 * Lobby host_id.
                 * @member {string|null|undefined} host_id
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.host_id = null;

                /**
                 * Lobby host_name.
                 * @member {string|null|undefined} host_name
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.host_name = null;

                /**
                 * Lobby hostless.
                 * @member {boolean|null|undefined} hostless
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.hostless = null;

                /**
                 * Lobby max_users.
                 * @member {number|null|undefined} max_users
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.max_users = null;

                /**
                 * Lobby is_hidden.
                 * @member {boolean|null|undefined} is_hidden
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.is_hidden = null;

                /**
                 * Lobby is_locked.
                 * @member {boolean|null|undefined} is_locked
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.is_locked = null;

                /**
                 * Lobby metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.metadata_json = null;

                /**
                 * Lobby is_passworded.
                 * @member {boolean|null|undefined} is_passworded
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.is_passworded = null;

                /**
                 * Lobby slowdown.
                 * @member {number|null|undefined} slowdown
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.slowdown = null;

                /**
                 * Lobby spectator_count.
                 * @member {number|null|undefined} spectator_count
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.spectator_count = null;

                /**
                 * Lobby members.
                 * @member {Array.<gamend.realtime.v1.UserBrief.$Properties>} members
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.members = $util.emptyArray;

                /**
                 * Lobby has_members.
                 * @member {boolean|null|undefined} has_members
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.has_members = null;

                /**
                 * Lobby metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 */
                Lobby.prototype.metadata_pb = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_title", {
                    get: $util.oneOfGetter($oneOfFields = ["title"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_host_id", {
                    get: $util.oneOfGetter($oneOfFields = ["host_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_host_name", {
                    get: $util.oneOfGetter($oneOfFields = ["host_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_hostless", {
                    get: $util.oneOfGetter($oneOfFields = ["hostless"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_max_users", {
                    get: $util.oneOfGetter($oneOfFields = ["max_users"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_is_hidden", {
                    get: $util.oneOfGetter($oneOfFields = ["is_hidden"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_is_locked", {
                    get: $util.oneOfGetter($oneOfFields = ["is_locked"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_is_passworded", {
                    get: $util.oneOfGetter($oneOfFields = ["is_passworded"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_slowdown", {
                    get: $util.oneOfGetter($oneOfFields = ["slowdown"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_spectator_count", {
                    get: $util.oneOfGetter($oneOfFields = ["spectator_count"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_has_members", {
                    get: $util.oneOfGetter($oneOfFields = ["has_members"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Lobby.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified Lobby message. Does not implicitly {@link gamend.realtime.v1.Lobby.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.Lobby
                 * @static
                 * @param {gamend.realtime.v1.Lobby.$Properties} message Lobby message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                Lobby.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.title);
                    if (message.host_id != null && $Object.hasOwnProperty.call(message, "host_id"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.host_id);
                    if (message.host_name != null && $Object.hasOwnProperty.call(message, "host_name"))
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.host_name);
                    if (message.hostless != null && $Object.hasOwnProperty.call(message, "hostless"))
                        writer.uint32(/* id 5, wireType 0 =*/40).bool(message.hostless);
                    if (message.max_users != null && $Object.hasOwnProperty.call(message, "max_users"))
                        writer.uint32(/* id 6, wireType 0 =*/48).int32(message.max_users);
                    if (message.is_hidden != null && $Object.hasOwnProperty.call(message, "is_hidden"))
                        writer.uint32(/* id 7, wireType 0 =*/56).bool(message.is_hidden);
                    if (message.is_locked != null && $Object.hasOwnProperty.call(message, "is_locked"))
                        writer.uint32(/* id 8, wireType 0 =*/64).bool(message.is_locked);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 9, wireType 2 =*/74).bytes(message.metadata_json);
                    if (message.is_passworded != null && $Object.hasOwnProperty.call(message, "is_passworded"))
                        writer.uint32(/* id 10, wireType 0 =*/80).bool(message.is_passworded);
                    if (message.slowdown != null && $Object.hasOwnProperty.call(message, "slowdown"))
                        writer.uint32(/* id 11, wireType 0 =*/88).int32(message.slowdown);
                    if (message.spectator_count != null && $Object.hasOwnProperty.call(message, "spectator_count"))
                        writer.uint32(/* id 12, wireType 0 =*/96).int32(message.spectator_count);
                    if (message.members != null && message.members.length)
                        for (let i = 0; i < message.members.length; ++i)
                            $root.gamend.realtime.v1.UserBrief.encode(message.members[i], writer.uint32(/* id 13, wireType 2 =*/106).fork(), _depth + 1).ldelim();
                    if (message.has_members != null && $Object.hasOwnProperty.call(message, "has_members"))
                        writer.uint32(/* id 14, wireType 0 =*/112).bool(message.has_members);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 15, wireType 2 =*/122).bytes(message.metadata_pb);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a Lobby message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.Lobby
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.Lobby & gamend.realtime.v1.Lobby.$Shape} Lobby
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                Lobby.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.Lobby();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.title = reader.stringVerify();
                                message._title = "title";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.host_id = reader.stringVerify();
                                message._host_id = "host_id";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.host_name = reader.stringVerify();
                                message._host_name = "host_name";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                message.hostless = reader.bool();
                                message._hostless = "hostless";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 0)
                                    break;
                                message.max_users = reader.int32();
                                message._max_users = "max_users";
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                message.is_hidden = reader.bool();
                                message._is_hidden = "is_hidden";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                message.is_locked = reader.bool();
                                message._is_locked = "is_locked";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 0)
                                    break;
                                message.is_passworded = reader.bool();
                                message._is_passworded = "is_passworded";
                                continue;
                            }
                        case 11: {
                                if (wireType !== 0)
                                    break;
                                message.slowdown = reader.int32();
                                message._slowdown = "slowdown";
                                continue;
                            }
                        case 12: {
                                if (wireType !== 0)
                                    break;
                                message.spectator_count = reader.int32();
                                message._spectator_count = "spectator_count";
                                continue;
                            }
                        case 13: {
                                if (wireType !== 2)
                                    break;
                                if (!(message.members && message.members.length))
                                    message.members = [];
                                message.members.push($root.gamend.realtime.v1.UserBrief.decode(reader, reader.uint32(), $undefined, _depth + 1));
                                continue;
                            }
                        case 14: {
                                if (wireType !== 0)
                                    break;
                                message.has_members = reader.bool();
                                message._has_members = "has_members";
                                continue;
                            }
                        case 15: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a Lobby message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.Lobby
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.Lobby} Lobby
                 */
                Lobby.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.Lobby)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.Lobby: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.Lobby();
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.title != null)
                        message.title = $String(object.title);
                    if (object.host_id != null)
                        message.host_id = $String(object.host_id);
                    if (object.host_name != null)
                        message.host_name = $String(object.host_name);
                    if (object.hostless != null)
                        message.hostless = $Boolean(object.hostless);
                    if (object.max_users != null)
                        message.max_users = object.max_users | 0;
                    if (object.is_hidden != null)
                        message.is_hidden = $Boolean(object.is_hidden);
                    if (object.is_locked != null)
                        message.is_locked = $Boolean(object.is_locked);
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.is_passworded != null)
                        message.is_passworded = $Boolean(object.is_passworded);
                    if (object.slowdown != null)
                        message.slowdown = object.slowdown | 0;
                    if (object.spectator_count != null)
                        message.spectator_count = object.spectator_count | 0;
                    if (object.members) {
                        if (!$Array.isArray(object.members))
                            throw $TypeError(".gamend.realtime.v1.Lobby.members: array expected");
                        message.members = $Array(object.members.length);
                        for (let i = 0; i < object.members.length; ++i) {
                            if (!$util.isObject(object.members[i]))
                                throw $TypeError(".gamend.realtime.v1.Lobby.members: object expected");
                            message.members[i] = $root.gamend.realtime.v1.UserBrief.fromObject(object.members[i], _depth + 1);
                        }
                    }
                    if (object.has_members != null)
                        message.has_members = $Boolean(object.has_members);
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    return message;
                };

                /**
                 * Creates a plain object from a Lobby message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.Lobby
                 * @static
                 * @param {gamend.realtime.v1.Lobby} message Lobby
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                Lobby.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.arrays || options.defaults)
                        object.members = [];
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title"))
                        object.title = message.title;
                    if (message.host_id != null && $Object.hasOwnProperty.call(message, "host_id"))
                        object.host_id = message.host_id;
                    if (message.host_name != null && $Object.hasOwnProperty.call(message, "host_name"))
                        object.host_name = message.host_name;
                    if (message.hostless != null && $Object.hasOwnProperty.call(message, "hostless"))
                        object.hostless = message.hostless;
                    if (message.max_users != null && $Object.hasOwnProperty.call(message, "max_users"))
                        object.max_users = message.max_users;
                    if (message.is_hidden != null && $Object.hasOwnProperty.call(message, "is_hidden"))
                        object.is_hidden = message.is_hidden;
                    if (message.is_locked != null && $Object.hasOwnProperty.call(message, "is_locked"))
                        object.is_locked = message.is_locked;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.is_passworded != null && $Object.hasOwnProperty.call(message, "is_passworded"))
                        object.is_passworded = message.is_passworded;
                    if (message.slowdown != null && $Object.hasOwnProperty.call(message, "slowdown"))
                        object.slowdown = message.slowdown;
                    if (message.spectator_count != null && $Object.hasOwnProperty.call(message, "spectator_count"))
                        object.spectator_count = message.spectator_count;
                    if (message.members && message.members.length) {
                        object.members = $Array(message.members.length);
                        for (let j = 0; j < message.members.length; ++j)
                            object.members[j] = $root.gamend.realtime.v1.UserBrief.toObject(message.members[j], options, _depth + 1);
                    }
                    if (message.has_members != null && $Object.hasOwnProperty.call(message, "has_members"))
                        object.has_members = message.has_members;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    return object;
                };

                /**
                 * Converts this Lobby to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.Lobby
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                Lobby.prototype.toJSON = function() {
                    return Lobby.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for Lobby
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.Lobby
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                Lobby.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.Lobby";
                };

                return Lobby;
            })();

            v1.Group = (function() {

                /**
                 * Properties of a Group.
                 * @typedef {Object} gamend.realtime.v1.Group.$Properties
                 * @property {string|null} [id] Group id
                 * @property {string|null} [title] Group title
                 * @property {string|null} [description] Group description
                 * @property {string|null} [type] Group type
                 * @property {number|null} [max_members] Group max_members
                 * @property {string|null} [creator_id] Group creator_id
                 * @property {string|null} [creator_name] Group creator_name
                 * @property {Uint8Array|null} [metadata_json] Group metadata_json
                 * @property {number|null} [member_count] Group member_count
                 * @property {number|null} [slowdown] Group slowdown
                 * @property {number|Long|null} [inserted_at_ms] Group inserted_at_ms
                 * @property {number|Long|null} [updated_at_ms] Group updated_at_ms
                 * @property {Uint8Array|null} [metadata_pb] Group metadata_pb
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a Group.
                 * @memberof gamend.realtime.v1
                 * @interface IGroup
                 * @augments gamend.realtime.v1.Group.$Properties
                 * @deprecated Use gamend.realtime.v1.Group.$Properties instead.
                 */

                /**
                 * Shape of a Group.
                 * @typedef {gamend.realtime.v1.Group.$Properties} gamend.realtime.v1.Group.$Shape
                 */

                /**
                 * Constructs a new Group.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a Group.
                 * @constructor
                 * @param {gamend.realtime.v1.Group.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const Group = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * Group id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.id = null;

                /**
                 * Group title.
                 * @member {string|null|undefined} title
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.title = null;

                /**
                 * Group description.
                 * @member {string|null|undefined} description
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.description = null;

                /**
                 * Group type.
                 * @member {string|null|undefined} type
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.type = null;

                /**
                 * Group max_members.
                 * @member {number|null|undefined} max_members
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.max_members = null;

                /**
                 * Group creator_id.
                 * @member {string|null|undefined} creator_id
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.creator_id = null;

                /**
                 * Group creator_name.
                 * @member {string|null|undefined} creator_name
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.creator_name = null;

                /**
                 * Group metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.metadata_json = null;

                /**
                 * Group member_count.
                 * @member {number|null|undefined} member_count
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.member_count = null;

                /**
                 * Group slowdown.
                 * @member {number|null|undefined} slowdown
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.slowdown = null;

                /**
                 * Group inserted_at_ms.
                 * @member {number|Long|null|undefined} inserted_at_ms
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.inserted_at_ms = null;

                /**
                 * Group updated_at_ms.
                 * @member {number|Long|null|undefined} updated_at_ms
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.updated_at_ms = null;

                /**
                 * Group metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 */
                Group.prototype.metadata_pb = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_title", {
                    get: $util.oneOfGetter($oneOfFields = ["title"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_description", {
                    get: $util.oneOfGetter($oneOfFields = ["description"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_type", {
                    get: $util.oneOfGetter($oneOfFields = ["type"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_max_members", {
                    get: $util.oneOfGetter($oneOfFields = ["max_members"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_creator_id", {
                    get: $util.oneOfGetter($oneOfFields = ["creator_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_creator_name", {
                    get: $util.oneOfGetter($oneOfFields = ["creator_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_member_count", {
                    get: $util.oneOfGetter($oneOfFields = ["member_count"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_slowdown", {
                    get: $util.oneOfGetter($oneOfFields = ["slowdown"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_inserted_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["inserted_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_updated_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["updated_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Group.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified Group message. Does not implicitly {@link gamend.realtime.v1.Group.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.Group
                 * @static
                 * @param {gamend.realtime.v1.Group.$Properties} message Group message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                Group.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.title);
                    if (message.description != null && $Object.hasOwnProperty.call(message, "description"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.description);
                    if (message.type != null && $Object.hasOwnProperty.call(message, "type"))
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.type);
                    if (message.max_members != null && $Object.hasOwnProperty.call(message, "max_members"))
                        writer.uint32(/* id 5, wireType 0 =*/40).int32(message.max_members);
                    if (message.creator_id != null && $Object.hasOwnProperty.call(message, "creator_id"))
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.creator_id);
                    if (message.creator_name != null && $Object.hasOwnProperty.call(message, "creator_name"))
                        writer.uint32(/* id 7, wireType 2 =*/58).string(message.creator_name);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 8, wireType 2 =*/66).bytes(message.metadata_json);
                    if (message.member_count != null && $Object.hasOwnProperty.call(message, "member_count"))
                        writer.uint32(/* id 9, wireType 0 =*/72).int32(message.member_count);
                    if (message.slowdown != null && $Object.hasOwnProperty.call(message, "slowdown"))
                        writer.uint32(/* id 10, wireType 0 =*/80).int32(message.slowdown);
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        writer.uint32(/* id 11, wireType 0 =*/88).int64(message.inserted_at_ms);
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        writer.uint32(/* id 12, wireType 0 =*/96).int64(message.updated_at_ms);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 13, wireType 2 =*/106).bytes(message.metadata_pb);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a Group message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.Group
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.Group & gamend.realtime.v1.Group.$Shape} Group
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                Group.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.Group();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.title = reader.stringVerify();
                                message._title = "title";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.description = reader.stringVerify();
                                message._description = "description";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.type = reader.stringVerify();
                                message._type = "type";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                message.max_members = reader.int32();
                                message._max_members = "max_members";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                message.creator_id = reader.stringVerify();
                                message._creator_id = "creator_id";
                                continue;
                            }
                        case 7: {
                                if (wireType !== 2)
                                    break;
                                message.creator_name = reader.stringVerify();
                                message._creator_name = "creator_name";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 0)
                                    break;
                                message.member_count = reader.int32();
                                message._member_count = "member_count";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 0)
                                    break;
                                message.slowdown = reader.int32();
                                message._slowdown = "slowdown";
                                continue;
                            }
                        case 11: {
                                if (wireType !== 0)
                                    break;
                                message.inserted_at_ms = reader.int64();
                                message._inserted_at_ms = "inserted_at_ms";
                                continue;
                            }
                        case 12: {
                                if (wireType !== 0)
                                    break;
                                message.updated_at_ms = reader.int64();
                                message._updated_at_ms = "updated_at_ms";
                                continue;
                            }
                        case 13: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a Group message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.Group
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.Group} Group
                 */
                Group.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.Group)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.Group: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.Group();
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.title != null)
                        message.title = $String(object.title);
                    if (object.description != null)
                        message.description = $String(object.description);
                    if (object.type != null)
                        message.type = $String(object.type);
                    if (object.max_members != null)
                        message.max_members = object.max_members | 0;
                    if (object.creator_id != null)
                        message.creator_id = $String(object.creator_id);
                    if (object.creator_name != null)
                        message.creator_name = $String(object.creator_name);
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.member_count != null)
                        message.member_count = object.member_count | 0;
                    if (object.slowdown != null)
                        message.slowdown = object.slowdown | 0;
                    if (object.inserted_at_ms != null)
                        if ($util.Long)
                            message.inserted_at_ms = $util.Long.fromValue(object.inserted_at_ms, false);
                        else if (typeof object.inserted_at_ms === "string")
                            message.inserted_at_ms = $parseInt(object.inserted_at_ms, 10);
                        else if (typeof object.inserted_at_ms === "number")
                            message.inserted_at_ms = object.inserted_at_ms;
                        else if (typeof object.inserted_at_ms === "object")
                            message.inserted_at_ms = new $util.LongBits(object.inserted_at_ms.low >>> 0, object.inserted_at_ms.high >>> 0).toNumber();
                    if (object.updated_at_ms != null)
                        if ($util.Long)
                            message.updated_at_ms = $util.Long.fromValue(object.updated_at_ms, false);
                        else if (typeof object.updated_at_ms === "string")
                            message.updated_at_ms = $parseInt(object.updated_at_ms, 10);
                        else if (typeof object.updated_at_ms === "number")
                            message.updated_at_ms = object.updated_at_ms;
                        else if (typeof object.updated_at_ms === "object")
                            message.updated_at_ms = new $util.LongBits(object.updated_at_ms.low >>> 0, object.updated_at_ms.high >>> 0).toNumber();
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    return message;
                };

                /**
                 * Creates a plain object from a Group message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.Group
                 * @static
                 * @param {gamend.realtime.v1.Group} message Group
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                Group.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.title != null && $Object.hasOwnProperty.call(message, "title"))
                        object.title = message.title;
                    if (message.description != null && $Object.hasOwnProperty.call(message, "description"))
                        object.description = message.description;
                    if (message.type != null && $Object.hasOwnProperty.call(message, "type"))
                        object.type = message.type;
                    if (message.max_members != null && $Object.hasOwnProperty.call(message, "max_members"))
                        object.max_members = message.max_members;
                    if (message.creator_id != null && $Object.hasOwnProperty.call(message, "creator_id"))
                        object.creator_id = message.creator_id;
                    if (message.creator_name != null && $Object.hasOwnProperty.call(message, "creator_name"))
                        object.creator_name = message.creator_name;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.member_count != null && $Object.hasOwnProperty.call(message, "member_count"))
                        object.member_count = message.member_count;
                    if (message.slowdown != null && $Object.hasOwnProperty.call(message, "slowdown"))
                        object.slowdown = message.slowdown;
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.inserted_at_ms = typeof message.inserted_at_ms === "number" ? $BigInt(message.inserted_at_ms) : $util.Long.fromBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.inserted_at_ms === "number")
                            object.inserted_at_ms = options.longs === $String ? $String(message.inserted_at_ms) : message.inserted_at_ms;
                        else
                            object.inserted_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.inserted_at_ms) : options.longs === $Number ? new $util.LongBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0).toNumber() : message.inserted_at_ms;
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.updated_at_ms = typeof message.updated_at_ms === "number" ? $BigInt(message.updated_at_ms) : $util.Long.fromBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.updated_at_ms === "number")
                            object.updated_at_ms = options.longs === $String ? $String(message.updated_at_ms) : message.updated_at_ms;
                        else
                            object.updated_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.updated_at_ms) : options.longs === $Number ? new $util.LongBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0).toNumber() : message.updated_at_ms;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    return object;
                };

                /**
                 * Converts this Group to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.Group
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                Group.prototype.toJSON = function() {
                    return Group.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for Group
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.Group
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                Group.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.Group";
                };

                return Group;
            })();

            v1.Party = (function() {

                /**
                 * Properties of a Party.
                 * @typedef {Object} gamend.realtime.v1.Party.$Properties
                 * @property {string|null} [id] Party id
                 * @property {string|null} [leader_id] Party leader_id
                 * @property {string|null} [leader_name] Party leader_name
                 * @property {number|null} [max_size] Party max_size
                 * @property {Uint8Array|null} [metadata_json] Party metadata_json
                 * @property {Array.<gamend.realtime.v1.UserBrief.$Properties>|null} [members] Party members
                 * @property {boolean|null} [has_members] Party has_members
                 * @property {number|Long|null} [inserted_at_ms] Party inserted_at_ms
                 * @property {number|Long|null} [updated_at_ms] Party updated_at_ms
                 * @property {Uint8Array|null} [metadata_pb] Party metadata_pb
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a Party.
                 * @memberof gamend.realtime.v1
                 * @interface IParty
                 * @augments gamend.realtime.v1.Party.$Properties
                 * @deprecated Use gamend.realtime.v1.Party.$Properties instead.
                 */

                /**
                 * Shape of a Party.
                 * @typedef {gamend.realtime.v1.Party.$Properties} gamend.realtime.v1.Party.$Shape
                 */

                /**
                 * Constructs a new Party.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a Party.
                 * @constructor
                 * @param {gamend.realtime.v1.Party.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const Party = function (properties) {
                    this.members = [];
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * Party id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.id = null;

                /**
                 * Party leader_id.
                 * @member {string|null|undefined} leader_id
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.leader_id = null;

                /**
                 * Party leader_name.
                 * @member {string|null|undefined} leader_name
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.leader_name = null;

                /**
                 * Party max_size.
                 * @member {number|null|undefined} max_size
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.max_size = null;

                /**
                 * Party metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.metadata_json = null;

                /**
                 * Party members.
                 * @member {Array.<gamend.realtime.v1.UserBrief.$Properties>} members
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.members = $util.emptyArray;

                /**
                 * Party has_members.
                 * @member {boolean|null|undefined} has_members
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.has_members = null;

                /**
                 * Party inserted_at_ms.
                 * @member {number|Long|null|undefined} inserted_at_ms
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.inserted_at_ms = null;

                /**
                 * Party updated_at_ms.
                 * @member {number|Long|null|undefined} updated_at_ms
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.updated_at_ms = null;

                /**
                 * Party metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 */
                Party.prototype.metadata_pb = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_leader_id", {
                    get: $util.oneOfGetter($oneOfFields = ["leader_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_leader_name", {
                    get: $util.oneOfGetter($oneOfFields = ["leader_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_max_size", {
                    get: $util.oneOfGetter($oneOfFields = ["max_size"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_has_members", {
                    get: $util.oneOfGetter($oneOfFields = ["has_members"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_inserted_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["inserted_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_updated_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["updated_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(Party.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified Party message. Does not implicitly {@link gamend.realtime.v1.Party.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.Party
                 * @static
                 * @param {gamend.realtime.v1.Party.$Properties} message Party message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                Party.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.leader_id != null && $Object.hasOwnProperty.call(message, "leader_id"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.leader_id);
                    if (message.leader_name != null && $Object.hasOwnProperty.call(message, "leader_name"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.leader_name);
                    if (message.max_size != null && $Object.hasOwnProperty.call(message, "max_size"))
                        writer.uint32(/* id 4, wireType 0 =*/32).int32(message.max_size);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 5, wireType 2 =*/42).bytes(message.metadata_json);
                    if (message.members != null && message.members.length)
                        for (let i = 0; i < message.members.length; ++i)
                            $root.gamend.realtime.v1.UserBrief.encode(message.members[i], writer.uint32(/* id 6, wireType 2 =*/50).fork(), _depth + 1).ldelim();
                    if (message.has_members != null && $Object.hasOwnProperty.call(message, "has_members"))
                        writer.uint32(/* id 7, wireType 0 =*/56).bool(message.has_members);
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        writer.uint32(/* id 8, wireType 0 =*/64).int64(message.inserted_at_ms);
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        writer.uint32(/* id 9, wireType 0 =*/72).int64(message.updated_at_ms);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 10, wireType 2 =*/82).bytes(message.metadata_pb);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a Party message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.Party
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.Party & gamend.realtime.v1.Party.$Shape} Party
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                Party.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.Party();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.leader_id = reader.stringVerify();
                                message._leader_id = "leader_id";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.leader_name = reader.stringVerify();
                                message._leader_name = "leader_name";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 0)
                                    break;
                                message.max_size = reader.int32();
                                message._max_size = "max_size";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                if (!(message.members && message.members.length))
                                    message.members = [];
                                message.members.push($root.gamend.realtime.v1.UserBrief.decode(reader, reader.uint32(), $undefined, _depth + 1));
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                message.has_members = reader.bool();
                                message._has_members = "has_members";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                message.inserted_at_ms = reader.int64();
                                message._inserted_at_ms = "inserted_at_ms";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 0)
                                    break;
                                message.updated_at_ms = reader.int64();
                                message._updated_at_ms = "updated_at_ms";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a Party message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.Party
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.Party} Party
                 */
                Party.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.Party)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.Party: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.Party();
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.leader_id != null)
                        message.leader_id = $String(object.leader_id);
                    if (object.leader_name != null)
                        message.leader_name = $String(object.leader_name);
                    if (object.max_size != null)
                        message.max_size = object.max_size | 0;
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.members) {
                        if (!$Array.isArray(object.members))
                            throw $TypeError(".gamend.realtime.v1.Party.members: array expected");
                        message.members = $Array(object.members.length);
                        for (let i = 0; i < object.members.length; ++i) {
                            if (!$util.isObject(object.members[i]))
                                throw $TypeError(".gamend.realtime.v1.Party.members: object expected");
                            message.members[i] = $root.gamend.realtime.v1.UserBrief.fromObject(object.members[i], _depth + 1);
                        }
                    }
                    if (object.has_members != null)
                        message.has_members = $Boolean(object.has_members);
                    if (object.inserted_at_ms != null)
                        if ($util.Long)
                            message.inserted_at_ms = $util.Long.fromValue(object.inserted_at_ms, false);
                        else if (typeof object.inserted_at_ms === "string")
                            message.inserted_at_ms = $parseInt(object.inserted_at_ms, 10);
                        else if (typeof object.inserted_at_ms === "number")
                            message.inserted_at_ms = object.inserted_at_ms;
                        else if (typeof object.inserted_at_ms === "object")
                            message.inserted_at_ms = new $util.LongBits(object.inserted_at_ms.low >>> 0, object.inserted_at_ms.high >>> 0).toNumber();
                    if (object.updated_at_ms != null)
                        if ($util.Long)
                            message.updated_at_ms = $util.Long.fromValue(object.updated_at_ms, false);
                        else if (typeof object.updated_at_ms === "string")
                            message.updated_at_ms = $parseInt(object.updated_at_ms, 10);
                        else if (typeof object.updated_at_ms === "number")
                            message.updated_at_ms = object.updated_at_ms;
                        else if (typeof object.updated_at_ms === "object")
                            message.updated_at_ms = new $util.LongBits(object.updated_at_ms.low >>> 0, object.updated_at_ms.high >>> 0).toNumber();
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    return message;
                };

                /**
                 * Creates a plain object from a Party message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.Party
                 * @static
                 * @param {gamend.realtime.v1.Party} message Party
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                Party.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.arrays || options.defaults)
                        object.members = [];
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.leader_id != null && $Object.hasOwnProperty.call(message, "leader_id"))
                        object.leader_id = message.leader_id;
                    if (message.leader_name != null && $Object.hasOwnProperty.call(message, "leader_name"))
                        object.leader_name = message.leader_name;
                    if (message.max_size != null && $Object.hasOwnProperty.call(message, "max_size"))
                        object.max_size = message.max_size;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.members && message.members.length) {
                        object.members = $Array(message.members.length);
                        for (let j = 0; j < message.members.length; ++j)
                            object.members[j] = $root.gamend.realtime.v1.UserBrief.toObject(message.members[j], options, _depth + 1);
                    }
                    if (message.has_members != null && $Object.hasOwnProperty.call(message, "has_members"))
                        object.has_members = message.has_members;
                    if (message.inserted_at_ms != null && $Object.hasOwnProperty.call(message, "inserted_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.inserted_at_ms = typeof message.inserted_at_ms === "number" ? $BigInt(message.inserted_at_ms) : $util.Long.fromBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.inserted_at_ms === "number")
                            object.inserted_at_ms = options.longs === $String ? $String(message.inserted_at_ms) : message.inserted_at_ms;
                        else
                            object.inserted_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.inserted_at_ms) : options.longs === $Number ? new $util.LongBits(message.inserted_at_ms.low >>> 0, message.inserted_at_ms.high >>> 0).toNumber() : message.inserted_at_ms;
                    if (message.updated_at_ms != null && $Object.hasOwnProperty.call(message, "updated_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.updated_at_ms = typeof message.updated_at_ms === "number" ? $BigInt(message.updated_at_ms) : $util.Long.fromBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.updated_at_ms === "number")
                            object.updated_at_ms = options.longs === $String ? $String(message.updated_at_ms) : message.updated_at_ms;
                        else
                            object.updated_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.updated_at_ms) : options.longs === $Number ? new $util.LongBits(message.updated_at_ms.low >>> 0, message.updated_at_ms.high >>> 0).toNumber() : message.updated_at_ms;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    return object;
                };

                /**
                 * Converts this Party to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.Party
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                Party.prototype.toJSON = function() {
                    return Party.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for Party
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.Party
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                Party.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.Party";
                };

                return Party;
            })();

            v1.MemberEvent = (function() {

                /**
                 * Properties of a MemberEvent.
                 * @typedef {Object} gamend.realtime.v1.MemberEvent.$Properties
                 * @property {string|null} [user_id] MemberEvent user_id
                 * @property {string|null} [display_name] MemberEvent display_name
                 * @property {string|null} [id] MemberEvent id
                 * @property {string|null} [profile_url] MemberEvent profile_url
                 * @property {Uint8Array|null} [metadata_json] MemberEvent metadata_json
                 * @property {boolean|null} [is_online] MemberEvent is_online
                 * @property {boolean|null} [is_activated] MemberEvent is_activated
                 * @property {number|Long|null} [last_seen_at_ms] MemberEvent last_seen_at_ms
                 * @property {string|null} [group_id] MemberEvent group_id
                 * @property {Uint8Array|null} [metadata_pb] MemberEvent metadata_pb
                 * @property {string|null} [username] MemberEvent username
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a MemberEvent.
                 * @memberof gamend.realtime.v1
                 * @interface IMemberEvent
                 * @augments gamend.realtime.v1.MemberEvent.$Properties
                 * @deprecated Use gamend.realtime.v1.MemberEvent.$Properties instead.
                 */

                /**
                 * Shape of a MemberEvent.
                 * @typedef {gamend.realtime.v1.MemberEvent.$Properties} gamend.realtime.v1.MemberEvent.$Shape
                 */

                /**
                 * Constructs a new MemberEvent.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a MemberEvent.
                 * @constructor
                 * @param {gamend.realtime.v1.MemberEvent.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const MemberEvent = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * MemberEvent user_id.
                 * @member {string} user_id
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.user_id = "";

                /**
                 * MemberEvent display_name.
                 * @member {string|null|undefined} display_name
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.display_name = null;

                /**
                 * MemberEvent id.
                 * @member {string|null|undefined} id
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.id = null;

                /**
                 * MemberEvent profile_url.
                 * @member {string|null|undefined} profile_url
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.profile_url = null;

                /**
                 * MemberEvent metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.metadata_json = null;

                /**
                 * MemberEvent is_online.
                 * @member {boolean|null|undefined} is_online
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.is_online = null;

                /**
                 * MemberEvent is_activated.
                 * @member {boolean|null|undefined} is_activated
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.is_activated = null;

                /**
                 * MemberEvent last_seen_at_ms.
                 * @member {number|Long|null|undefined} last_seen_at_ms
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.last_seen_at_ms = null;

                /**
                 * MemberEvent group_id.
                 * @member {string|null|undefined} group_id
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.group_id = null;

                /**
                 * MemberEvent metadata_pb.
                 * @member {Uint8Array|null|undefined} metadata_pb
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.metadata_pb = null;

                /**
                 * MemberEvent username.
                 * @member {string|null|undefined} username
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 */
                MemberEvent.prototype.username = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_display_name", {
                    get: $util.oneOfGetter($oneOfFields = ["display_name"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_id", {
                    get: $util.oneOfGetter($oneOfFields = ["id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_profile_url", {
                    get: $util.oneOfGetter($oneOfFields = ["profile_url"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_is_online", {
                    get: $util.oneOfGetter($oneOfFields = ["is_online"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_is_activated", {
                    get: $util.oneOfGetter($oneOfFields = ["is_activated"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_last_seen_at_ms", {
                    get: $util.oneOfGetter($oneOfFields = ["last_seen_at_ms"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_group_id", {
                    get: $util.oneOfGetter($oneOfFields = ["group_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_metadata_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(MemberEvent.prototype, "_username", {
                    get: $util.oneOfGetter($oneOfFields = ["username"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified MemberEvent message. Does not implicitly {@link gamend.realtime.v1.MemberEvent.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @static
                 * @param {gamend.realtime.v1.MemberEvent.$Properties} message MemberEvent message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                MemberEvent.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id") && message.user_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.user_id);
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.display_name);
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.id);
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.profile_url);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 5, wireType 2 =*/42).bytes(message.metadata_json);
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        writer.uint32(/* id 6, wireType 0 =*/48).bool(message.is_online);
                    if (message.is_activated != null && $Object.hasOwnProperty.call(message, "is_activated"))
                        writer.uint32(/* id 7, wireType 0 =*/56).bool(message.is_activated);
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        writer.uint32(/* id 8, wireType 0 =*/64).int64(message.last_seen_at_ms);
                    if (message.group_id != null && $Object.hasOwnProperty.call(message, "group_id"))
                        writer.uint32(/* id 9, wireType 2 =*/74).string(message.group_id);
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        writer.uint32(/* id 10, wireType 2 =*/82).bytes(message.metadata_pb);
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        writer.uint32(/* id 11, wireType 2 =*/90).string(message.username);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a MemberEvent message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.MemberEvent & gamend.realtime.v1.MemberEvent.$Shape} MemberEvent
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                MemberEvent.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.MemberEvent(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.user_id = value;
                                else
                                    delete message.user_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.display_name = reader.stringVerify();
                                message._display_name = "display_name";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.id = reader.stringVerify();
                                message._id = "id";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.profile_url = reader.stringVerify();
                                message._profile_url = "profile_url";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 0)
                                    break;
                                message.is_online = reader.bool();
                                message._is_online = "is_online";
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                message.is_activated = reader.bool();
                                message._is_activated = "is_activated";
                                continue;
                            }
                        case 8: {
                                if (wireType !== 0)
                                    break;
                                message.last_seen_at_ms = reader.int64();
                                message._last_seen_at_ms = "last_seen_at_ms";
                                continue;
                            }
                        case 9: {
                                if (wireType !== 2)
                                    break;
                                message.group_id = reader.stringVerify();
                                message._group_id = "group_id";
                                continue;
                            }
                        case 10: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_pb = reader.bytes();
                                message._metadata_pb = "metadata_pb";
                                continue;
                            }
                        case 11: {
                                if (wireType !== 2)
                                    break;
                                message.username = reader.stringVerify();
                                message._username = "username";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a MemberEvent message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.MemberEvent} MemberEvent
                 */
                MemberEvent.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.MemberEvent)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.MemberEvent: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.MemberEvent();
                    if (object.user_id != null)
                        if (typeof object.user_id !== "string" || object.user_id.length)
                            message.user_id = $String(object.user_id);
                    if (object.display_name != null)
                        message.display_name = $String(object.display_name);
                    if (object.id != null)
                        message.id = $String(object.id);
                    if (object.profile_url != null)
                        message.profile_url = $String(object.profile_url);
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.is_online != null)
                        message.is_online = $Boolean(object.is_online);
                    if (object.is_activated != null)
                        message.is_activated = $Boolean(object.is_activated);
                    if (object.last_seen_at_ms != null)
                        if ($util.Long)
                            message.last_seen_at_ms = $util.Long.fromValue(object.last_seen_at_ms, false);
                        else if (typeof object.last_seen_at_ms === "string")
                            message.last_seen_at_ms = $parseInt(object.last_seen_at_ms, 10);
                        else if (typeof object.last_seen_at_ms === "number")
                            message.last_seen_at_ms = object.last_seen_at_ms;
                        else if (typeof object.last_seen_at_ms === "object")
                            message.last_seen_at_ms = new $util.LongBits(object.last_seen_at_ms.low >>> 0, object.last_seen_at_ms.high >>> 0).toNumber();
                    if (object.group_id != null)
                        message.group_id = $String(object.group_id);
                    if (object.metadata_pb != null)
                        if (typeof object.metadata_pb === "string")
                            $util.base64.decode(object.metadata_pb, message.metadata_pb = $util.newBuffer($util.base64.length(object.metadata_pb)), 0);
                        else if (object.metadata_pb.length >= 0)
                            message.metadata_pb = object.metadata_pb;
                    if (object.username != null)
                        message.username = $String(object.username);
                    return message;
                };

                /**
                 * Creates a plain object from a MemberEvent message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @static
                 * @param {gamend.realtime.v1.MemberEvent} message MemberEvent
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                MemberEvent.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.user_id = "";
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        object.user_id = message.user_id;
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        object.display_name = message.display_name;
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.profile_url != null && $Object.hasOwnProperty.call(message, "profile_url"))
                        object.profile_url = message.profile_url;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.is_online != null && $Object.hasOwnProperty.call(message, "is_online"))
                        object.is_online = message.is_online;
                    if (message.is_activated != null && $Object.hasOwnProperty.call(message, "is_activated"))
                        object.is_activated = message.is_activated;
                    if (message.last_seen_at_ms != null && $Object.hasOwnProperty.call(message, "last_seen_at_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.last_seen_at_ms = typeof message.last_seen_at_ms === "number" ? $BigInt(message.last_seen_at_ms) : $util.Long.fromBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.last_seen_at_ms === "number")
                            object.last_seen_at_ms = options.longs === $String ? $String(message.last_seen_at_ms) : message.last_seen_at_ms;
                        else
                            object.last_seen_at_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.last_seen_at_ms) : options.longs === $Number ? new $util.LongBits(message.last_seen_at_ms.low >>> 0, message.last_seen_at_ms.high >>> 0).toNumber() : message.last_seen_at_ms;
                    if (message.group_id != null && $Object.hasOwnProperty.call(message, "group_id"))
                        object.group_id = message.group_id;
                    if (message.metadata_pb != null && $Object.hasOwnProperty.call(message, "metadata_pb"))
                        object.metadata_pb = options.bytes === $String ? $util.base64.encode(message.metadata_pb, 0, message.metadata_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_pb) : message.metadata_pb;
                    if (message.username != null && $Object.hasOwnProperty.call(message, "username"))
                        object.username = message.username;
                    return object;
                };

                /**
                 * Converts this MemberEvent to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                MemberEvent.prototype.toJSON = function() {
                    return MemberEvent.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for MemberEvent
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.MemberEvent
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                MemberEvent.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.MemberEvent";
                };

                return MemberEvent;
            })();

            v1.EntityId = (function() {

                /**
                 * Properties of an EntityId.
                 * @typedef {Object} gamend.realtime.v1.EntityId.$Properties
                 * @property {string|null} [id] EntityId id
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of an EntityId.
                 * @memberof gamend.realtime.v1
                 * @interface IEntityId
                 * @augments gamend.realtime.v1.EntityId.$Properties
                 * @deprecated Use gamend.realtime.v1.EntityId.$Properties instead.
                 */

                /**
                 * Shape of an EntityId.
                 * @typedef {gamend.realtime.v1.EntityId.$Properties} gamend.realtime.v1.EntityId.$Shape
                 */

                /**
                 * Constructs a new EntityId.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents an EntityId.
                 * @constructor
                 * @param {gamend.realtime.v1.EntityId.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const EntityId = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * EntityId id.
                 * @member {string} id
                 * @memberof gamend.realtime.v1.EntityId
                 * @instance
                 */
                EntityId.prototype.id = "";

                /**
                 * Encodes the specified EntityId message. Does not implicitly {@link gamend.realtime.v1.EntityId.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.EntityId
                 * @static
                 * @param {gamend.realtime.v1.EntityId.$Properties} message EntityId message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                EntityId.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes an EntityId message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.EntityId
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.EntityId & gamend.realtime.v1.EntityId.$Shape} EntityId
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                EntityId.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.EntityId(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates an EntityId message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.EntityId
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.EntityId} EntityId
                 */
                EntityId.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.EntityId)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.EntityId: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.EntityId();
                    if (object.id != null)
                        if (typeof object.id !== "string" || object.id.length)
                            message.id = $String(object.id);
                    return message;
                };

                /**
                 * Creates a plain object from an EntityId message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.EntityId
                 * @static
                 * @param {gamend.realtime.v1.EntityId} message EntityId
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                EntityId.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.id = "";
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    return object;
                };

                /**
                 * Converts this EntityId to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.EntityId
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                EntityId.prototype.toJSON = function() {
                    return EntityId.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for EntityId
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.EntityId
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                EntityId.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.EntityId";
                };

                return EntityId;
            })();

            v1.PartyRef = (function() {

                /**
                 * Properties of a PartyRef.
                 * @typedef {Object} gamend.realtime.v1.PartyRef.$Properties
                 * @property {string|null} [party_id] PartyRef party_id
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a PartyRef.
                 * @memberof gamend.realtime.v1
                 * @interface IPartyRef
                 * @augments gamend.realtime.v1.PartyRef.$Properties
                 * @deprecated Use gamend.realtime.v1.PartyRef.$Properties instead.
                 */

                /**
                 * Shape of a PartyRef.
                 * @typedef {gamend.realtime.v1.PartyRef.$Properties} gamend.realtime.v1.PartyRef.$Shape
                 */

                /**
                 * Constructs a new PartyRef.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a PartyRef.
                 * @constructor
                 * @param {gamend.realtime.v1.PartyRef.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const PartyRef = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * PartyRef party_id.
                 * @member {string} party_id
                 * @memberof gamend.realtime.v1.PartyRef
                 * @instance
                 */
                PartyRef.prototype.party_id = "";

                /**
                 * Encodes the specified PartyRef message. Does not implicitly {@link gamend.realtime.v1.PartyRef.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.PartyRef
                 * @static
                 * @param {gamend.realtime.v1.PartyRef.$Properties} message PartyRef message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                PartyRef.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id") && message.party_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.party_id);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a PartyRef message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.PartyRef
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.PartyRef & gamend.realtime.v1.PartyRef.$Shape} PartyRef
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                PartyRef.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.PartyRef(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.party_id = value;
                                else
                                    delete message.party_id;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a PartyRef message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.PartyRef
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.PartyRef} PartyRef
                 */
                PartyRef.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.PartyRef)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.PartyRef: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.PartyRef();
                    if (object.party_id != null)
                        if (typeof object.party_id !== "string" || object.party_id.length)
                            message.party_id = $String(object.party_id);
                    return message;
                };

                /**
                 * Creates a plain object from a PartyRef message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.PartyRef
                 * @static
                 * @param {gamend.realtime.v1.PartyRef} message PartyRef
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                PartyRef.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.party_id = "";
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id"))
                        object.party_id = message.party_id;
                    return object;
                };

                /**
                 * Converts this PartyRef to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.PartyRef
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                PartyRef.prototype.toJSON = function() {
                    return PartyRef.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for PartyRef
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.PartyRef
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                PartyRef.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.PartyRef";
                };

                return PartyRef;
            })();

            v1.HostChanged = (function() {

                /**
                 * Properties of a HostChanged.
                 * @typedef {Object} gamend.realtime.v1.HostChanged.$Properties
                 * @property {string|null} [new_host_id] HostChanged new_host_id
                 * @property {string|null} [display_name] HostChanged display_name
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a HostChanged.
                 * @memberof gamend.realtime.v1
                 * @interface IHostChanged
                 * @augments gamend.realtime.v1.HostChanged.$Properties
                 * @deprecated Use gamend.realtime.v1.HostChanged.$Properties instead.
                 */

                /**
                 * Shape of a HostChanged.
                 * @typedef {gamend.realtime.v1.HostChanged.$Properties} gamend.realtime.v1.HostChanged.$Shape
                 */

                /**
                 * Constructs a new HostChanged.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a HostChanged.
                 * @constructor
                 * @param {gamend.realtime.v1.HostChanged.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const HostChanged = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * HostChanged new_host_id.
                 * @member {string} new_host_id
                 * @memberof gamend.realtime.v1.HostChanged
                 * @instance
                 */
                HostChanged.prototype.new_host_id = "";

                /**
                 * HostChanged display_name.
                 * @member {string} display_name
                 * @memberof gamend.realtime.v1.HostChanged
                 * @instance
                 */
                HostChanged.prototype.display_name = "";

                /**
                 * Encodes the specified HostChanged message. Does not implicitly {@link gamend.realtime.v1.HostChanged.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.HostChanged
                 * @static
                 * @param {gamend.realtime.v1.HostChanged.$Properties} message HostChanged message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                HostChanged.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.new_host_id != null && $Object.hasOwnProperty.call(message, "new_host_id") && message.new_host_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.new_host_id);
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name") && message.display_name !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.display_name);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a HostChanged message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.HostChanged
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.HostChanged & gamend.realtime.v1.HostChanged.$Shape} HostChanged
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                HostChanged.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.HostChanged(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.new_host_id = value;
                                else
                                    delete message.new_host_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.display_name = value;
                                else
                                    delete message.display_name;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a HostChanged message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.HostChanged
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.HostChanged} HostChanged
                 */
                HostChanged.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.HostChanged)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.HostChanged: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.HostChanged();
                    if (object.new_host_id != null)
                        if (typeof object.new_host_id !== "string" || object.new_host_id.length)
                            message.new_host_id = $String(object.new_host_id);
                    if (object.display_name != null)
                        if (typeof object.display_name !== "string" || object.display_name.length)
                            message.display_name = $String(object.display_name);
                    return message;
                };

                /**
                 * Creates a plain object from a HostChanged message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.HostChanged
                 * @static
                 * @param {gamend.realtime.v1.HostChanged} message HostChanged
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                HostChanged.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.new_host_id = "";
                        object.display_name = "";
                    }
                    if (message.new_host_id != null && $Object.hasOwnProperty.call(message, "new_host_id"))
                        object.new_host_id = message.new_host_id;
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        object.display_name = message.display_name;
                    return object;
                };

                /**
                 * Converts this HostChanged to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.HostChanged
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                HostChanged.prototype.toJSON = function() {
                    return HostChanged.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for HostChanged
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.HostChanged
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                HostChanged.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.HostChanged";
                };

                return HostChanged;
            })();

            v1.GroupInviteEvent = (function() {

                /**
                 * Properties of a GroupInviteEvent.
                 * @typedef {Object} gamend.realtime.v1.GroupInviteEvent.$Properties
                 * @property {string|null} [group_id] GroupInviteEvent group_id
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a GroupInviteEvent.
                 * @memberof gamend.realtime.v1
                 * @interface IGroupInviteEvent
                 * @augments gamend.realtime.v1.GroupInviteEvent.$Properties
                 * @deprecated Use gamend.realtime.v1.GroupInviteEvent.$Properties instead.
                 */

                /**
                 * Shape of a GroupInviteEvent.
                 * @typedef {gamend.realtime.v1.GroupInviteEvent.$Properties} gamend.realtime.v1.GroupInviteEvent.$Shape
                 */

                /**
                 * Constructs a new GroupInviteEvent.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a GroupInviteEvent.
                 * @constructor
                 * @param {gamend.realtime.v1.GroupInviteEvent.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const GroupInviteEvent = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * GroupInviteEvent group_id.
                 * @member {string} group_id
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @instance
                 */
                GroupInviteEvent.prototype.group_id = "";

                /**
                 * Encodes the specified GroupInviteEvent message. Does not implicitly {@link gamend.realtime.v1.GroupInviteEvent.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @static
                 * @param {gamend.realtime.v1.GroupInviteEvent.$Properties} message GroupInviteEvent message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                GroupInviteEvent.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.group_id != null && $Object.hasOwnProperty.call(message, "group_id") && message.group_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.group_id);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a GroupInviteEvent message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.GroupInviteEvent & gamend.realtime.v1.GroupInviteEvent.$Shape} GroupInviteEvent
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                GroupInviteEvent.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.GroupInviteEvent(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.group_id = value;
                                else
                                    delete message.group_id;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a GroupInviteEvent message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.GroupInviteEvent} GroupInviteEvent
                 */
                GroupInviteEvent.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.GroupInviteEvent)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.GroupInviteEvent: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.GroupInviteEvent();
                    if (object.group_id != null)
                        if (typeof object.group_id !== "string" || object.group_id.length)
                            message.group_id = $String(object.group_id);
                    return message;
                };

                /**
                 * Creates a plain object from a GroupInviteEvent message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @static
                 * @param {gamend.realtime.v1.GroupInviteEvent} message GroupInviteEvent
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                GroupInviteEvent.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.group_id = "";
                    if (message.group_id != null && $Object.hasOwnProperty.call(message, "group_id"))
                        object.group_id = message.group_id;
                    return object;
                };

                /**
                 * Converts this GroupInviteEvent to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                GroupInviteEvent.prototype.toJSON = function() {
                    return GroupInviteEvent.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for GroupInviteEvent
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.GroupInviteEvent
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                GroupInviteEvent.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.GroupInviteEvent";
                };

                return GroupInviteEvent;
            })();

            v1.PartyInviteEvent = (function() {

                /**
                 * Properties of a PartyInviteEvent.
                 * @typedef {Object} gamend.realtime.v1.PartyInviteEvent.$Properties
                 * @property {string|null} [party_id] PartyInviteEvent party_id
                 * @property {string|null} [user_id] PartyInviteEvent user_id
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a PartyInviteEvent.
                 * @memberof gamend.realtime.v1
                 * @interface IPartyInviteEvent
                 * @augments gamend.realtime.v1.PartyInviteEvent.$Properties
                 * @deprecated Use gamend.realtime.v1.PartyInviteEvent.$Properties instead.
                 */

                /**
                 * Shape of a PartyInviteEvent.
                 * @typedef {gamend.realtime.v1.PartyInviteEvent.$Properties} gamend.realtime.v1.PartyInviteEvent.$Shape
                 */

                /**
                 * Constructs a new PartyInviteEvent.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a PartyInviteEvent.
                 * @constructor
                 * @param {gamend.realtime.v1.PartyInviteEvent.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const PartyInviteEvent = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * PartyInviteEvent party_id.
                 * @member {string} party_id
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @instance
                 */
                PartyInviteEvent.prototype.party_id = "";

                /**
                 * PartyInviteEvent user_id.
                 * @member {string} user_id
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @instance
                 */
                PartyInviteEvent.prototype.user_id = "";

                /**
                 * Encodes the specified PartyInviteEvent message. Does not implicitly {@link gamend.realtime.v1.PartyInviteEvent.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @static
                 * @param {gamend.realtime.v1.PartyInviteEvent.$Properties} message PartyInviteEvent message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                PartyInviteEvent.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id") && message.party_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.party_id);
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id") && message.user_id !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.user_id);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a PartyInviteEvent message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.PartyInviteEvent & gamend.realtime.v1.PartyInviteEvent.$Shape} PartyInviteEvent
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                PartyInviteEvent.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.PartyInviteEvent(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.party_id = value;
                                else
                                    delete message.party_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.user_id = value;
                                else
                                    delete message.user_id;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a PartyInviteEvent message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.PartyInviteEvent} PartyInviteEvent
                 */
                PartyInviteEvent.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.PartyInviteEvent)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.PartyInviteEvent: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.PartyInviteEvent();
                    if (object.party_id != null)
                        if (typeof object.party_id !== "string" || object.party_id.length)
                            message.party_id = $String(object.party_id);
                    if (object.user_id != null)
                        if (typeof object.user_id !== "string" || object.user_id.length)
                            message.user_id = $String(object.user_id);
                    return message;
                };

                /**
                 * Creates a plain object from a PartyInviteEvent message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @static
                 * @param {gamend.realtime.v1.PartyInviteEvent} message PartyInviteEvent
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                PartyInviteEvent.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.party_id = "";
                        object.user_id = "";
                    }
                    if (message.party_id != null && $Object.hasOwnProperty.call(message, "party_id"))
                        object.party_id = message.party_id;
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        object.user_id = message.user_id;
                    return object;
                };

                /**
                 * Converts this PartyInviteEvent to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                PartyInviteEvent.prototype.toJSON = function() {
                    return PartyInviteEvent.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for PartyInviteEvent
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.PartyInviteEvent
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                PartyInviteEvent.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.PartyInviteEvent";
                };

                return PartyInviteEvent;
            })();

            v1.TournamentEvent = (function() {

                /**
                 * Properties of a TournamentEvent.
                 * @typedef {Object} gamend.realtime.v1.TournamentEvent.$Properties
                 * @property {string|null} [tournament_id] TournamentEvent tournament_id
                 * @property {string|null} [slug] TournamentEvent slug
                 * @property {string|null} [state] TournamentEvent state
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a TournamentEvent.
                 * @memberof gamend.realtime.v1
                 * @interface ITournamentEvent
                 * @augments gamend.realtime.v1.TournamentEvent.$Properties
                 * @deprecated Use gamend.realtime.v1.TournamentEvent.$Properties instead.
                 */

                /**
                 * Shape of a TournamentEvent.
                 * @typedef {gamend.realtime.v1.TournamentEvent.$Properties} gamend.realtime.v1.TournamentEvent.$Shape
                 */

                /**
                 * Constructs a new TournamentEvent.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a TournamentEvent.
                 * @constructor
                 * @param {gamend.realtime.v1.TournamentEvent.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const TournamentEvent = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * TournamentEvent tournament_id.
                 * @member {string} tournament_id
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @instance
                 */
                TournamentEvent.prototype.tournament_id = "";

                /**
                 * TournamentEvent slug.
                 * @member {string} slug
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @instance
                 */
                TournamentEvent.prototype.slug = "";

                /**
                 * TournamentEvent state.
                 * @member {string} state
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @instance
                 */
                TournamentEvent.prototype.state = "";

                /**
                 * Encodes the specified TournamentEvent message. Does not implicitly {@link gamend.realtime.v1.TournamentEvent.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @static
                 * @param {gamend.realtime.v1.TournamentEvent.$Properties} message TournamentEvent message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                TournamentEvent.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.tournament_id != null && $Object.hasOwnProperty.call(message, "tournament_id") && message.tournament_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.tournament_id);
                    if (message.slug != null && $Object.hasOwnProperty.call(message, "slug") && message.slug !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.slug);
                    if (message.state != null && $Object.hasOwnProperty.call(message, "state") && message.state !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.state);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a TournamentEvent message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.TournamentEvent & gamend.realtime.v1.TournamentEvent.$Shape} TournamentEvent
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                TournamentEvent.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.TournamentEvent(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.tournament_id = value;
                                else
                                    delete message.tournament_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.slug = value;
                                else
                                    delete message.slug;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.state = value;
                                else
                                    delete message.state;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a TournamentEvent message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.TournamentEvent} TournamentEvent
                 */
                TournamentEvent.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.TournamentEvent)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.TournamentEvent: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.TournamentEvent();
                    if (object.tournament_id != null)
                        if (typeof object.tournament_id !== "string" || object.tournament_id.length)
                            message.tournament_id = $String(object.tournament_id);
                    if (object.slug != null)
                        if (typeof object.slug !== "string" || object.slug.length)
                            message.slug = $String(object.slug);
                    if (object.state != null)
                        if (typeof object.state !== "string" || object.state.length)
                            message.state = $String(object.state);
                    return message;
                };

                /**
                 * Creates a plain object from a TournamentEvent message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @static
                 * @param {gamend.realtime.v1.TournamentEvent} message TournamentEvent
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                TournamentEvent.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.tournament_id = "";
                        object.slug = "";
                        object.state = "";
                    }
                    if (message.tournament_id != null && $Object.hasOwnProperty.call(message, "tournament_id"))
                        object.tournament_id = message.tournament_id;
                    if (message.slug != null && $Object.hasOwnProperty.call(message, "slug"))
                        object.slug = message.slug;
                    if (message.state != null && $Object.hasOwnProperty.call(message, "state"))
                        object.state = message.state;
                    return object;
                };

                /**
                 * Converts this TournamentEvent to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                TournamentEvent.prototype.toJSON = function() {
                    return TournamentEvent.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for TournamentEvent
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.TournamentEvent
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                TournamentEvent.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.TournamentEvent";
                };

                return TournamentEvent;
            })();

            v1.TournamentMatchEvent = (function() {

                /**
                 * Properties of a TournamentMatchEvent.
                 * @typedef {Object} gamend.realtime.v1.TournamentMatchEvent.$Properties
                 * @property {string|null} [tournament_id] TournamentMatchEvent tournament_id
                 * @property {string|null} [slug] TournamentMatchEvent slug
                 * @property {string|null} [match_id] TournamentMatchEvent match_id
                 * @property {number|null} [round] TournamentMatchEvent round
                 * @property {number|Long|null} [deadline_ms] TournamentMatchEvent deadline_ms
                 * @property {string|null} [winner_entry_id] TournamentMatchEvent winner_entry_id
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a TournamentMatchEvent.
                 * @memberof gamend.realtime.v1
                 * @interface ITournamentMatchEvent
                 * @augments gamend.realtime.v1.TournamentMatchEvent.$Properties
                 * @deprecated Use gamend.realtime.v1.TournamentMatchEvent.$Properties instead.
                 */

                /**
                 * Shape of a TournamentMatchEvent.
                 * @typedef {gamend.realtime.v1.TournamentMatchEvent.$Properties} gamend.realtime.v1.TournamentMatchEvent.$Shape
                 */

                /**
                 * Constructs a new TournamentMatchEvent.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a TournamentMatchEvent.
                 * @constructor
                 * @param {gamend.realtime.v1.TournamentMatchEvent.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const TournamentMatchEvent = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * TournamentMatchEvent tournament_id.
                 * @member {string} tournament_id
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.tournament_id = "";

                /**
                 * TournamentMatchEvent slug.
                 * @member {string} slug
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.slug = "";

                /**
                 * TournamentMatchEvent match_id.
                 * @member {string} match_id
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.match_id = "";

                /**
                 * TournamentMatchEvent round.
                 * @member {number} round
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.round = 0;

                /**
                 * TournamentMatchEvent deadline_ms.
                 * @member {number|Long} deadline_ms
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.deadline_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                /**
                 * TournamentMatchEvent winner_entry_id.
                 * @member {string} winner_entry_id
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 */
                TournamentMatchEvent.prototype.winner_entry_id = "";

                /**
                 * Encodes the specified TournamentMatchEvent message. Does not implicitly {@link gamend.realtime.v1.TournamentMatchEvent.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @static
                 * @param {gamend.realtime.v1.TournamentMatchEvent.$Properties} message TournamentMatchEvent message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                TournamentMatchEvent.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.tournament_id != null && $Object.hasOwnProperty.call(message, "tournament_id") && message.tournament_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.tournament_id);
                    if (message.slug != null && $Object.hasOwnProperty.call(message, "slug") && message.slug !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.slug);
                    if (message.match_id != null && $Object.hasOwnProperty.call(message, "match_id") && message.match_id !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.match_id);
                    if (message.round != null && $Object.hasOwnProperty.call(message, "round") && message.round !== 0)
                        writer.uint32(/* id 4, wireType 0 =*/32).int32(message.round);
                    if (message.deadline_ms != null && $Object.hasOwnProperty.call(message, "deadline_ms") && (typeof message.deadline_ms === "object" ? message.deadline_ms.low || message.deadline_ms.high : message.deadline_ms !== 0))
                        writer.uint32(/* id 5, wireType 0 =*/40).int64(message.deadline_ms);
                    if (message.winner_entry_id != null && $Object.hasOwnProperty.call(message, "winner_entry_id") && message.winner_entry_id !== "")
                        writer.uint32(/* id 6, wireType 2 =*/50).string(message.winner_entry_id);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a TournamentMatchEvent message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.TournamentMatchEvent & gamend.realtime.v1.TournamentMatchEvent.$Shape} TournamentMatchEvent
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                TournamentMatchEvent.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.TournamentMatchEvent(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.tournament_id = value;
                                else
                                    delete message.tournament_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.slug = value;
                                else
                                    delete message.slug;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.match_id = value;
                                else
                                    delete message.match_id;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.int32())
                                    message.round = value;
                                else
                                    delete message.round;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.deadline_ms = value;
                                else
                                    delete message.deadline_ms;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.winner_entry_id = value;
                                else
                                    delete message.winner_entry_id;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a TournamentMatchEvent message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.TournamentMatchEvent} TournamentMatchEvent
                 */
                TournamentMatchEvent.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.TournamentMatchEvent)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.TournamentMatchEvent: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.TournamentMatchEvent();
                    if (object.tournament_id != null)
                        if (typeof object.tournament_id !== "string" || object.tournament_id.length)
                            message.tournament_id = $String(object.tournament_id);
                    if (object.slug != null)
                        if (typeof object.slug !== "string" || object.slug.length)
                            message.slug = $String(object.slug);
                    if (object.match_id != null)
                        if (typeof object.match_id !== "string" || object.match_id.length)
                            message.match_id = $String(object.match_id);
                    if (object.round != null)
                        if ($Number(object.round) !== 0)
                            message.round = object.round | 0;
                    if (object.deadline_ms != null)
                        if (typeof object.deadline_ms === "object" ? object.deadline_ms.low || object.deadline_ms.high : $Number(object.deadline_ms) !== 0)
                            if ($util.Long)
                                message.deadline_ms = $util.Long.fromValue(object.deadline_ms, false);
                            else if (typeof object.deadline_ms === "string")
                                message.deadline_ms = $parseInt(object.deadline_ms, 10);
                            else if (typeof object.deadline_ms === "number")
                                message.deadline_ms = object.deadline_ms;
                            else if (typeof object.deadline_ms === "object")
                                message.deadline_ms = new $util.LongBits(object.deadline_ms.low >>> 0, object.deadline_ms.high >>> 0).toNumber();
                    if (object.winner_entry_id != null)
                        if (typeof object.winner_entry_id !== "string" || object.winner_entry_id.length)
                            message.winner_entry_id = $String(object.winner_entry_id);
                    return message;
                };

                /**
                 * Creates a plain object from a TournamentMatchEvent message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @static
                 * @param {gamend.realtime.v1.TournamentMatchEvent} message TournamentMatchEvent
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                TournamentMatchEvent.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.tournament_id = "";
                        object.slug = "";
                        object.match_id = "";
                        object.round = 0;
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.deadline_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.deadline_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                        object.winner_entry_id = "";
                    }
                    if (message.tournament_id != null && $Object.hasOwnProperty.call(message, "tournament_id"))
                        object.tournament_id = message.tournament_id;
                    if (message.slug != null && $Object.hasOwnProperty.call(message, "slug"))
                        object.slug = message.slug;
                    if (message.match_id != null && $Object.hasOwnProperty.call(message, "match_id"))
                        object.match_id = message.match_id;
                    if (message.round != null && $Object.hasOwnProperty.call(message, "round"))
                        object.round = message.round;
                    if (message.deadline_ms != null && $Object.hasOwnProperty.call(message, "deadline_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.deadline_ms = typeof message.deadline_ms === "number" ? $BigInt(message.deadline_ms) : $util.Long.fromBits(message.deadline_ms.low >>> 0, message.deadline_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.deadline_ms === "number")
                            object.deadline_ms = options.longs === $String ? $String(message.deadline_ms) : message.deadline_ms;
                        else
                            object.deadline_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.deadline_ms) : options.longs === $Number ? new $util.LongBits(message.deadline_ms.low >>> 0, message.deadline_ms.high >>> 0).toNumber() : message.deadline_ms;
                    if (message.winner_entry_id != null && $Object.hasOwnProperty.call(message, "winner_entry_id"))
                        object.winner_entry_id = message.winner_entry_id;
                    return object;
                };

                /**
                 * Converts this TournamentMatchEvent to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                TournamentMatchEvent.prototype.toJSON = function() {
                    return TournamentMatchEvent.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for TournamentMatchEvent
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.TournamentMatchEvent
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                TournamentMatchEvent.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.TournamentMatchEvent";
                };

                return TournamentMatchEvent;
            })();

            v1.MatchmakingFound = (function() {

                /**
                 * Properties of a MatchmakingFound.
                 * @typedef {Object} gamend.realtime.v1.MatchmakingFound.$Properties
                 * @property {string|null} [lobby_id] MatchmakingFound lobby_id
                 * @property {Object.<string,string>|null} [match_params] MatchmakingFound match_params
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a MatchmakingFound.
                 * @memberof gamend.realtime.v1
                 * @interface IMatchmakingFound
                 * @augments gamend.realtime.v1.MatchmakingFound.$Properties
                 * @deprecated Use gamend.realtime.v1.MatchmakingFound.$Properties instead.
                 */

                /**
                 * Shape of a MatchmakingFound.
                 * @typedef {gamend.realtime.v1.MatchmakingFound.$Properties} gamend.realtime.v1.MatchmakingFound.$Shape
                 */

                /**
                 * Constructs a new MatchmakingFound.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a MatchmakingFound.
                 * @constructor
                 * @param {gamend.realtime.v1.MatchmakingFound.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const MatchmakingFound = function (properties) {
                    this.match_params = {};
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * MatchmakingFound lobby_id.
                 * @member {string} lobby_id
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @instance
                 */
                MatchmakingFound.prototype.lobby_id = "";

                /**
                 * MatchmakingFound match_params.
                 * @member {Object.<string,string>} match_params
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @instance
                 */
                MatchmakingFound.prototype.match_params = $util.emptyObject;

                /**
                 * Encodes the specified MatchmakingFound message. Does not implicitly {@link gamend.realtime.v1.MatchmakingFound.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @static
                 * @param {gamend.realtime.v1.MatchmakingFound.$Properties} message MatchmakingFound message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                MatchmakingFound.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id") && message.lobby_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.lobby_id);
                    if (message.match_params != null && $Object.hasOwnProperty.call(message, "match_params"))
                        for (let keys = $Object.keys(message.match_params), i = 0; i < keys.length; ++i)
                            writer.uint32(/* id 2, wireType 2 =*/18).fork().uint32(/* id 1, wireType 2 =*/10).string(keys[i]).uint32(/* id 2, wireType 2 =*/18).string(message.match_params[keys[i]]).ldelim();
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a MatchmakingFound message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.MatchmakingFound & gamend.realtime.v1.MatchmakingFound.$Shape} MatchmakingFound
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                MatchmakingFound.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.MatchmakingFound(), key, value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.lobby_id = value;
                                else
                                    delete message.lobby_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if (message.match_params === $util.emptyObject)
                                    message.match_params = {};
                                let end2 = reader.uint32() + reader.pos;
                                key = "";
                                value = "";
                                while (reader.pos < end2) {
                                    let tag2 = reader.tag();
                                    wireType = tag2 & 7;
                                    switch (tag2 >>>= 3) {
                                    case 1:
                                        if (wireType !== 2)
                                            break;
                                        key = reader.stringVerify();
                                        continue;
                                    case 2:
                                        if (wireType !== 2)
                                            break;
                                        value = reader.stringVerify();
                                        continue;
                                    }
                                    reader.skipType(wireType, _depth, tag2);
                                }
                                if (key === "__proto__")
                                    $util.makeProp(message.match_params, key);
                                message.match_params[key] = value;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a MatchmakingFound message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.MatchmakingFound} MatchmakingFound
                 */
                MatchmakingFound.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.MatchmakingFound)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.MatchmakingFound: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.MatchmakingFound();
                    if (object.lobby_id != null)
                        if (typeof object.lobby_id !== "string" || object.lobby_id.length)
                            message.lobby_id = $String(object.lobby_id);
                    if (object.match_params) {
                        if (!$util.isObject(object.match_params))
                            throw $TypeError(".gamend.realtime.v1.MatchmakingFound.match_params: object expected");
                        message.match_params = {};
                        for (let keys = $Object.keys(object.match_params), i = 0; i < keys.length; ++i) {
                            if (keys[i] === "__proto__")
                                $util.makeProp(message.match_params, keys[i]);
                            message.match_params[keys[i]] = $String(object.match_params[keys[i]]);
                        }
                    }
                    return message;
                };

                /**
                 * Creates a plain object from a MatchmakingFound message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @static
                 * @param {gamend.realtime.v1.MatchmakingFound} message MatchmakingFound
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                MatchmakingFound.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.objects || options.defaults)
                        object.match_params = {};
                    if (options.defaults)
                        object.lobby_id = "";
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        object.lobby_id = message.lobby_id;
                    let keys2;
                    if (message.match_params && (keys2 = $Object.keys(message.match_params)).length) {
                        object.match_params = {};
                        for (let j = 0; j < keys2.length; ++j) {
                            if (keys2[j] === "__proto__")
                                $util.makeProp(object.match_params, keys2[j]);
                            object.match_params[keys2[j]] = message.match_params[keys2[j]];
                        }
                    }
                    return object;
                };

                /**
                 * Converts this MatchmakingFound to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                MatchmakingFound.prototype.toJSON = function() {
                    return MatchmakingFound.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for MatchmakingFound
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.MatchmakingFound
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                MatchmakingFound.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.MatchmakingFound";
                };

                return MatchmakingFound;
            })();

            v1.ReadyCheckParticipant = (function() {

                /**
                 * Properties of a ReadyCheckParticipant.
                 * @typedef {Object} gamend.realtime.v1.ReadyCheckParticipant.$Properties
                 * @property {string|null} [user_id] ReadyCheckParticipant user_id
                 * @property {string|null} [display_name] ReadyCheckParticipant display_name
                 * @property {string|null} [state] ReadyCheckParticipant state
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a ReadyCheckParticipant.
                 * @memberof gamend.realtime.v1
                 * @interface IReadyCheckParticipant
                 * @augments gamend.realtime.v1.ReadyCheckParticipant.$Properties
                 * @deprecated Use gamend.realtime.v1.ReadyCheckParticipant.$Properties instead.
                 */

                /**
                 * Shape of a ReadyCheckParticipant.
                 * @typedef {gamend.realtime.v1.ReadyCheckParticipant.$Properties} gamend.realtime.v1.ReadyCheckParticipant.$Shape
                 */

                /**
                 * Constructs a new ReadyCheckParticipant.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a ReadyCheckParticipant.
                 * @constructor
                 * @param {gamend.realtime.v1.ReadyCheckParticipant.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const ReadyCheckParticipant = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * ReadyCheckParticipant user_id.
                 * @member {string} user_id
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @instance
                 */
                ReadyCheckParticipant.prototype.user_id = "";

                /**
                 * ReadyCheckParticipant display_name.
                 * @member {string} display_name
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @instance
                 */
                ReadyCheckParticipant.prototype.display_name = "";

                /**
                 * ReadyCheckParticipant state.
                 * @member {string} state
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @instance
                 */
                ReadyCheckParticipant.prototype.state = "";

                /**
                 * Encodes the specified ReadyCheckParticipant message. Does not implicitly {@link gamend.realtime.v1.ReadyCheckParticipant.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @static
                 * @param {gamend.realtime.v1.ReadyCheckParticipant.$Properties} message ReadyCheckParticipant message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                ReadyCheckParticipant.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id") && message.user_id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.user_id);
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name") && message.display_name !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.display_name);
                    if (message.state != null && $Object.hasOwnProperty.call(message, "state") && message.state !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.state);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a ReadyCheckParticipant message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.ReadyCheckParticipant & gamend.realtime.v1.ReadyCheckParticipant.$Shape} ReadyCheckParticipant
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                ReadyCheckParticipant.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.ReadyCheckParticipant(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.user_id = value;
                                else
                                    delete message.user_id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.display_name = value;
                                else
                                    delete message.display_name;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.state = value;
                                else
                                    delete message.state;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a ReadyCheckParticipant message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.ReadyCheckParticipant} ReadyCheckParticipant
                 */
                ReadyCheckParticipant.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.ReadyCheckParticipant)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.ReadyCheckParticipant: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.ReadyCheckParticipant();
                    if (object.user_id != null)
                        if (typeof object.user_id !== "string" || object.user_id.length)
                            message.user_id = $String(object.user_id);
                    if (object.display_name != null)
                        if (typeof object.display_name !== "string" || object.display_name.length)
                            message.display_name = $String(object.display_name);
                    if (object.state != null)
                        if (typeof object.state !== "string" || object.state.length)
                            message.state = $String(object.state);
                    return message;
                };

                /**
                 * Creates a plain object from a ReadyCheckParticipant message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @static
                 * @param {gamend.realtime.v1.ReadyCheckParticipant} message ReadyCheckParticipant
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                ReadyCheckParticipant.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.user_id = "";
                        object.display_name = "";
                        object.state = "";
                    }
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        object.user_id = message.user_id;
                    if (message.display_name != null && $Object.hasOwnProperty.call(message, "display_name"))
                        object.display_name = message.display_name;
                    if (message.state != null && $Object.hasOwnProperty.call(message, "state"))
                        object.state = message.state;
                    return object;
                };

                /**
                 * Converts this ReadyCheckParticipant to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                ReadyCheckParticipant.prototype.toJSON = function() {
                    return ReadyCheckParticipant.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for ReadyCheckParticipant
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.ReadyCheckParticipant
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                ReadyCheckParticipant.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.ReadyCheckParticipant";
                };

                return ReadyCheckParticipant;
            })();

            v1.ReadyCheckState = (function() {

                /**
                 * Properties of a ReadyCheckState.
                 * @typedef {Object} gamend.realtime.v1.ReadyCheckState.$Properties
                 * @property {string|null} [id] ReadyCheckState id
                 * @property {string|null} [kind] ReadyCheckState kind
                 * @property {string|null} [status] ReadyCheckState status
                 * @property {string|null} [lobby_id] ReadyCheckState lobby_id
                 * @property {number|Long|null} [deadline_ms] ReadyCheckState deadline_ms
                 * @property {number|null} [total] ReadyCheckState total
                 * @property {number|null} [ready_count] ReadyCheckState ready_count
                 * @property {string|null} [your_state] ReadyCheckState your_state
                 * @property {string|null} [reason] ReadyCheckState reason
                 * @property {Array.<gamend.realtime.v1.ReadyCheckParticipant.$Properties>|null} [participants] ReadyCheckState participants
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a ReadyCheckState.
                 * @memberof gamend.realtime.v1
                 * @interface IReadyCheckState
                 * @augments gamend.realtime.v1.ReadyCheckState.$Properties
                 * @deprecated Use gamend.realtime.v1.ReadyCheckState.$Properties instead.
                 */

                /**
                 * Shape of a ReadyCheckState.
                 * @typedef {gamend.realtime.v1.ReadyCheckState.$Properties} gamend.realtime.v1.ReadyCheckState.$Shape
                 */

                /**
                 * Constructs a new ReadyCheckState.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a ReadyCheckState.
                 * @constructor
                 * @param {gamend.realtime.v1.ReadyCheckState.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const ReadyCheckState = function (properties) {
                    this.participants = [];
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * ReadyCheckState id.
                 * @member {string} id
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.id = "";

                /**
                 * ReadyCheckState kind.
                 * @member {string} kind
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.kind = "";

                /**
                 * ReadyCheckState status.
                 * @member {string} status
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.status = "";

                /**
                 * ReadyCheckState lobby_id.
                 * @member {string} lobby_id
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.lobby_id = "";

                /**
                 * ReadyCheckState deadline_ms.
                 * @member {number|Long} deadline_ms
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.deadline_ms = $util.Long ? $util.Long.fromBits(0,0,false) : 0;

                /**
                 * ReadyCheckState total.
                 * @member {number} total
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.total = 0;

                /**
                 * ReadyCheckState ready_count.
                 * @member {number} ready_count
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.ready_count = 0;

                /**
                 * ReadyCheckState your_state.
                 * @member {string} your_state
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.your_state = "";

                /**
                 * ReadyCheckState reason.
                 * @member {string} reason
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.reason = "";

                /**
                 * ReadyCheckState participants.
                 * @member {Array.<gamend.realtime.v1.ReadyCheckParticipant.$Properties>} participants
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 */
                ReadyCheckState.prototype.participants = $util.emptyArray;

                /**
                 * Encodes the specified ReadyCheckState message. Does not implicitly {@link gamend.realtime.v1.ReadyCheckState.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @static
                 * @param {gamend.realtime.v1.ReadyCheckState.$Properties} message ReadyCheckState message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                ReadyCheckState.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.id);
                    if (message.kind != null && $Object.hasOwnProperty.call(message, "kind") && message.kind !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.kind);
                    if (message.status != null && $Object.hasOwnProperty.call(message, "status") && message.status !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.status);
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id") && message.lobby_id !== "")
                        writer.uint32(/* id 4, wireType 2 =*/34).string(message.lobby_id);
                    if (message.deadline_ms != null && $Object.hasOwnProperty.call(message, "deadline_ms") && (typeof message.deadline_ms === "object" ? message.deadline_ms.low || message.deadline_ms.high : message.deadline_ms !== 0))
                        writer.uint32(/* id 5, wireType 0 =*/40).int64(message.deadline_ms);
                    if (message.total != null && $Object.hasOwnProperty.call(message, "total") && message.total !== 0)
                        writer.uint32(/* id 6, wireType 0 =*/48).int32(message.total);
                    if (message.ready_count != null && $Object.hasOwnProperty.call(message, "ready_count") && message.ready_count !== 0)
                        writer.uint32(/* id 7, wireType 0 =*/56).int32(message.ready_count);
                    if (message.your_state != null && $Object.hasOwnProperty.call(message, "your_state") && message.your_state !== "")
                        writer.uint32(/* id 8, wireType 2 =*/66).string(message.your_state);
                    if (message.reason != null && $Object.hasOwnProperty.call(message, "reason") && message.reason !== "")
                        writer.uint32(/* id 9, wireType 2 =*/74).string(message.reason);
                    if (message.participants != null && message.participants.length)
                        for (let i = 0; i < message.participants.length; ++i)
                            $root.gamend.realtime.v1.ReadyCheckParticipant.encode(message.participants[i], writer.uint32(/* id 10, wireType 2 =*/82).fork(), _depth + 1).ldelim();
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a ReadyCheckState message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.ReadyCheckState & gamend.realtime.v1.ReadyCheckState.$Shape} ReadyCheckState
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                ReadyCheckState.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.ReadyCheckState(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.kind = value;
                                else
                                    delete message.kind;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.status = value;
                                else
                                    delete message.status;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.lobby_id = value;
                                else
                                    delete message.lobby_id;
                                continue;
                            }
                        case 5: {
                                if (wireType !== 0)
                                    break;
                                if (typeof (value = reader.int64()) === "object" ? value.low || value.high : value !== 0)
                                    message.deadline_ms = value;
                                else
                                    delete message.deadline_ms;
                                continue;
                            }
                        case 6: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.int32())
                                    message.total = value;
                                else
                                    delete message.total;
                                continue;
                            }
                        case 7: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.int32())
                                    message.ready_count = value;
                                else
                                    delete message.ready_count;
                                continue;
                            }
                        case 8: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.your_state = value;
                                else
                                    delete message.your_state;
                                continue;
                            }
                        case 9: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.reason = value;
                                else
                                    delete message.reason;
                                continue;
                            }
                        case 10: {
                                if (wireType !== 2)
                                    break;
                                if (!(message.participants && message.participants.length))
                                    message.participants = [];
                                message.participants.push($root.gamend.realtime.v1.ReadyCheckParticipant.decode(reader, reader.uint32(), $undefined, _depth + 1));
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a ReadyCheckState message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.ReadyCheckState} ReadyCheckState
                 */
                ReadyCheckState.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.ReadyCheckState)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.ReadyCheckState: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.ReadyCheckState();
                    if (object.id != null)
                        if (typeof object.id !== "string" || object.id.length)
                            message.id = $String(object.id);
                    if (object.kind != null)
                        if (typeof object.kind !== "string" || object.kind.length)
                            message.kind = $String(object.kind);
                    if (object.status != null)
                        if (typeof object.status !== "string" || object.status.length)
                            message.status = $String(object.status);
                    if (object.lobby_id != null)
                        if (typeof object.lobby_id !== "string" || object.lobby_id.length)
                            message.lobby_id = $String(object.lobby_id);
                    if (object.deadline_ms != null)
                        if (typeof object.deadline_ms === "object" ? object.deadline_ms.low || object.deadline_ms.high : $Number(object.deadline_ms) !== 0)
                            if ($util.Long)
                                message.deadline_ms = $util.Long.fromValue(object.deadline_ms, false);
                            else if (typeof object.deadline_ms === "string")
                                message.deadline_ms = $parseInt(object.deadline_ms, 10);
                            else if (typeof object.deadline_ms === "number")
                                message.deadline_ms = object.deadline_ms;
                            else if (typeof object.deadline_ms === "object")
                                message.deadline_ms = new $util.LongBits(object.deadline_ms.low >>> 0, object.deadline_ms.high >>> 0).toNumber();
                    if (object.total != null)
                        if ($Number(object.total) !== 0)
                            message.total = object.total | 0;
                    if (object.ready_count != null)
                        if ($Number(object.ready_count) !== 0)
                            message.ready_count = object.ready_count | 0;
                    if (object.your_state != null)
                        if (typeof object.your_state !== "string" || object.your_state.length)
                            message.your_state = $String(object.your_state);
                    if (object.reason != null)
                        if (typeof object.reason !== "string" || object.reason.length)
                            message.reason = $String(object.reason);
                    if (object.participants) {
                        if (!$Array.isArray(object.participants))
                            throw $TypeError(".gamend.realtime.v1.ReadyCheckState.participants: array expected");
                        message.participants = $Array(object.participants.length);
                        for (let i = 0; i < object.participants.length; ++i) {
                            if (!$util.isObject(object.participants[i]))
                                throw $TypeError(".gamend.realtime.v1.ReadyCheckState.participants: object expected");
                            message.participants[i] = $root.gamend.realtime.v1.ReadyCheckParticipant.fromObject(object.participants[i], _depth + 1);
                        }
                    }
                    return message;
                };

                /**
                 * Creates a plain object from a ReadyCheckState message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @static
                 * @param {gamend.realtime.v1.ReadyCheckState} message ReadyCheckState
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                ReadyCheckState.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.arrays || options.defaults)
                        object.participants = [];
                    if (options.defaults) {
                        object.id = "";
                        object.kind = "";
                        object.status = "";
                        object.lobby_id = "";
                        if ($util.Long) {
                            let long = new $util.Long(0, 0, false);
                            object.deadline_ms = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
                        } else
                            object.deadline_ms = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
                        object.total = 0;
                        object.ready_count = 0;
                        object.your_state = "";
                        object.reason = "";
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.kind != null && $Object.hasOwnProperty.call(message, "kind"))
                        object.kind = message.kind;
                    if (message.status != null && $Object.hasOwnProperty.call(message, "status"))
                        object.status = message.status;
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        object.lobby_id = message.lobby_id;
                    if (message.deadline_ms != null && $Object.hasOwnProperty.call(message, "deadline_ms"))
                        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
                            object.deadline_ms = typeof message.deadline_ms === "number" ? $BigInt(message.deadline_ms) : $util.Long.fromBits(message.deadline_ms.low >>> 0, message.deadline_ms.high >>> 0, false).toBigInt();
                        else if (typeof message.deadline_ms === "number")
                            object.deadline_ms = options.longs === $String ? $String(message.deadline_ms) : message.deadline_ms;
                        else
                            object.deadline_ms = options.longs === $String ? $util.Long.prototype.toString.call(message.deadline_ms) : options.longs === $Number ? new $util.LongBits(message.deadline_ms.low >>> 0, message.deadline_ms.high >>> 0).toNumber() : message.deadline_ms;
                    if (message.total != null && $Object.hasOwnProperty.call(message, "total"))
                        object.total = message.total;
                    if (message.ready_count != null && $Object.hasOwnProperty.call(message, "ready_count"))
                        object.ready_count = message.ready_count;
                    if (message.your_state != null && $Object.hasOwnProperty.call(message, "your_state"))
                        object.your_state = message.your_state;
                    if (message.reason != null && $Object.hasOwnProperty.call(message, "reason"))
                        object.reason = message.reason;
                    if (message.participants && message.participants.length) {
                        object.participants = $Array(message.participants.length);
                        for (let j = 0; j < message.participants.length; ++j)
                            object.participants[j] = $root.gamend.realtime.v1.ReadyCheckParticipant.toObject(message.participants[j], options, _depth + 1);
                    }
                    return object;
                };

                /**
                 * Converts this ReadyCheckState to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                ReadyCheckState.prototype.toJSON = function() {
                    return ReadyCheckState.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for ReadyCheckState
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.ReadyCheckState
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                ReadyCheckState.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.ReadyCheckState";
                };

                return ReadyCheckState;
            })();

            v1.KvEntry = (function() {

                /**
                 * Properties of a KvEntry.
                 * @typedef {Object} gamend.realtime.v1.KvEntry.$Properties
                 * @property {string|null} [key] KvEntry key
                 * @property {string|null} [user_id] KvEntry user_id
                 * @property {string|null} [lobby_id] KvEntry lobby_id
                 * @property {Uint8Array|null} [data_json] KvEntry data_json
                 * @property {Uint8Array|null} [metadata_json] KvEntry metadata_json
                 * @property {Uint8Array|null} [data_pb] KvEntry data_pb
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a KvEntry.
                 * @memberof gamend.realtime.v1
                 * @interface IKvEntry
                 * @augments gamend.realtime.v1.KvEntry.$Properties
                 * @deprecated Use gamend.realtime.v1.KvEntry.$Properties instead.
                 */

                /**
                 * Shape of a KvEntry.
                 * @typedef {gamend.realtime.v1.KvEntry.$Properties} gamend.realtime.v1.KvEntry.$Shape
                 */

                /**
                 * Constructs a new KvEntry.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a KvEntry.
                 * @constructor
                 * @param {gamend.realtime.v1.KvEntry.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const KvEntry = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * KvEntry key.
                 * @member {string} key
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.key = "";

                /**
                 * KvEntry user_id.
                 * @member {string|null|undefined} user_id
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.user_id = null;

                /**
                 * KvEntry lobby_id.
                 * @member {string|null|undefined} lobby_id
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.lobby_id = null;

                /**
                 * KvEntry data_json.
                 * @member {Uint8Array|null|undefined} data_json
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.data_json = null;

                /**
                 * KvEntry metadata_json.
                 * @member {Uint8Array|null|undefined} metadata_json
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.metadata_json = null;

                /**
                 * KvEntry data_pb.
                 * @member {Uint8Array|null|undefined} data_pb
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 */
                KvEntry.prototype.data_pb = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(KvEntry.prototype, "_user_id", {
                    get: $util.oneOfGetter($oneOfFields = ["user_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(KvEntry.prototype, "_lobby_id", {
                    get: $util.oneOfGetter($oneOfFields = ["lobby_id"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(KvEntry.prototype, "_data_json", {
                    get: $util.oneOfGetter($oneOfFields = ["data_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(KvEntry.prototype, "_metadata_json", {
                    get: $util.oneOfGetter($oneOfFields = ["metadata_json"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                // Virtual OneOf for proto3 optional field
                $Object.defineProperty(KvEntry.prototype, "_data_pb", {
                    get: $util.oneOfGetter($oneOfFields = ["data_pb"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified KvEntry message. Does not implicitly {@link gamend.realtime.v1.KvEntry.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.KvEntry
                 * @static
                 * @param {gamend.realtime.v1.KvEntry.$Properties} message KvEntry message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                KvEntry.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.key != null && $Object.hasOwnProperty.call(message, "key") && message.key !== "")
                        writer.uint32(/* id 1, wireType 2 =*/10).string(message.key);
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.user_id);
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.lobby_id);
                    if (message.data_json != null && $Object.hasOwnProperty.call(message, "data_json"))
                        writer.uint32(/* id 4, wireType 2 =*/34).bytes(message.data_json);
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        writer.uint32(/* id 5, wireType 2 =*/42).bytes(message.metadata_json);
                    if (message.data_pb != null && $Object.hasOwnProperty.call(message, "data_pb"))
                        writer.uint32(/* id 6, wireType 2 =*/50).bytes(message.data_pb);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a KvEntry message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.KvEntry
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.KvEntry & gamend.realtime.v1.KvEntry.$Shape} KvEntry
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                KvEntry.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.KvEntry(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.key = value;
                                else
                                    delete message.key;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.user_id = reader.stringVerify();
                                message._user_id = "user_id";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.lobby_id = reader.stringVerify();
                                message._lobby_id = "lobby_id";
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.data_json = reader.bytes();
                                message._data_json = "data_json";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                message.metadata_json = reader.bytes();
                                message._metadata_json = "metadata_json";
                                continue;
                            }
                        case 6: {
                                if (wireType !== 2)
                                    break;
                                message.data_pb = reader.bytes();
                                message._data_pb = "data_pb";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a KvEntry message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.KvEntry
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.KvEntry} KvEntry
                 */
                KvEntry.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.KvEntry)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.KvEntry: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.KvEntry();
                    if (object.key != null)
                        if (typeof object.key !== "string" || object.key.length)
                            message.key = $String(object.key);
                    if (object.user_id != null)
                        message.user_id = $String(object.user_id);
                    if (object.lobby_id != null)
                        message.lobby_id = $String(object.lobby_id);
                    if (object.data_json != null)
                        if (typeof object.data_json === "string")
                            $util.base64.decode(object.data_json, message.data_json = $util.newBuffer($util.base64.length(object.data_json)), 0);
                        else if (object.data_json.length >= 0)
                            message.data_json = object.data_json;
                    if (object.metadata_json != null)
                        if (typeof object.metadata_json === "string")
                            $util.base64.decode(object.metadata_json, message.metadata_json = $util.newBuffer($util.base64.length(object.metadata_json)), 0);
                        else if (object.metadata_json.length >= 0)
                            message.metadata_json = object.metadata_json;
                    if (object.data_pb != null)
                        if (typeof object.data_pb === "string")
                            $util.base64.decode(object.data_pb, message.data_pb = $util.newBuffer($util.base64.length(object.data_pb)), 0);
                        else if (object.data_pb.length >= 0)
                            message.data_pb = object.data_pb;
                    return message;
                };

                /**
                 * Creates a plain object from a KvEntry message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.KvEntry
                 * @static
                 * @param {gamend.realtime.v1.KvEntry} message KvEntry
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                KvEntry.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.key = "";
                    if (message.key != null && $Object.hasOwnProperty.call(message, "key"))
                        object.key = message.key;
                    if (message.user_id != null && $Object.hasOwnProperty.call(message, "user_id"))
                        object.user_id = message.user_id;
                    if (message.lobby_id != null && $Object.hasOwnProperty.call(message, "lobby_id"))
                        object.lobby_id = message.lobby_id;
                    if (message.data_json != null && $Object.hasOwnProperty.call(message, "data_json"))
                        object.data_json = options.bytes === $String ? $util.base64.encode(message.data_json, 0, message.data_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.data_json) : message.data_json;
                    if (message.metadata_json != null && $Object.hasOwnProperty.call(message, "metadata_json"))
                        object.metadata_json = options.bytes === $String ? $util.base64.encode(message.metadata_json, 0, message.metadata_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.metadata_json) : message.metadata_json;
                    if (message.data_pb != null && $Object.hasOwnProperty.call(message, "data_pb"))
                        object.data_pb = options.bytes === $String ? $util.base64.encode(message.data_pb, 0, message.data_pb.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.data_pb) : message.data_pb;
                    return object;
                };

                /**
                 * Converts this KvEntry to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.KvEntry
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                KvEntry.prototype.toJSON = function() {
                    return KvEntry.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for KvEntry
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.KvEntry
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                KvEntry.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.KvEntry";
                };

                return KvEntry;
            })();

            v1.RpcCall = (function() {

                /**
                 * Properties of a RpcCall.
                 * @typedef {Object} gamend.realtime.v1.RpcCall.$Properties
                 * @property {number|null} [id] RpcCall id
                 * @property {string|null} [plugin] RpcCall plugin
                 * @property {string|null} [fn] RpcCall fn
                 * @property {Uint8Array|null} [args_json] RpcCall args_json
                 * @property {Uint8Array|null} [args_raw] RpcCall args_raw
                 * @property {"args_json"|"args_raw"} [args] RpcCall args
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a RpcCall.
                 * @memberof gamend.realtime.v1
                 * @interface IRpcCall
                 * @augments gamend.realtime.v1.RpcCall.$Properties
                 * @deprecated Use gamend.realtime.v1.RpcCall.$Properties instead.
                 */

                /**
                 * Narrowed shape of a RpcCall.
                 * @typedef {{
                 *   id?: number|null;
                 *   plugin?: string|null;
                 *   fn?: string|null;
                 *   args_json?: Uint8Array|null;
                 *   args_raw?: Uint8Array|null;
                 *   $unknowns?: Array.<Uint8Array>;
                 * } & (
                 *   ({ args?: undefined; args_json?: null; args_raw?: null }|{ args?: "args_json"; args_json: Uint8Array; args_raw?: null }|{ args?: "args_raw"; args_json?: null; args_raw: Uint8Array })
                 * )} gamend.realtime.v1.RpcCall.$Shape
                 */

                /**
                 * Constructs a new RpcCall.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a RpcCall.
                 * @constructor
                 * @param {gamend.realtime.v1.RpcCall.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const RpcCall = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * RpcCall id.
                 * @member {number} id
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                RpcCall.prototype.id = 0;

                /**
                 * RpcCall plugin.
                 * @member {string} plugin
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                RpcCall.prototype.plugin = "";

                /**
                 * RpcCall fn.
                 * @member {string} fn
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                RpcCall.prototype.fn = "";

                /**
                 * RpcCall args_json.
                 * @member {Uint8Array|null|undefined} args_json
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                RpcCall.prototype.args_json = null;

                /**
                 * RpcCall args_raw.
                 * @member {Uint8Array|null|undefined} args_raw
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                RpcCall.prototype.args_raw = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                /**
                 * RpcCall args.
                 * @member {"args_json"|"args_raw"|undefined} args
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 */
                $Object.defineProperty(RpcCall.prototype, "args", {
                    get: $util.oneOfGetter($oneOfFields = ["args_json", "args_raw"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified RpcCall message. Does not implicitly {@link gamend.realtime.v1.RpcCall.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.RpcCall
                 * @static
                 * @param {gamend.realtime.v1.RpcCall.$Properties} message RpcCall message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                RpcCall.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== 0)
                        writer.uint32(/* id 1, wireType 0 =*/8).uint32(message.id);
                    if (message.plugin != null && $Object.hasOwnProperty.call(message, "plugin") && message.plugin !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.plugin);
                    if (message.fn != null && $Object.hasOwnProperty.call(message, "fn") && message.fn !== "")
                        writer.uint32(/* id 3, wireType 2 =*/26).string(message.fn);
                    if (message.args_json != null && $Object.hasOwnProperty.call(message, "args_json"))
                        writer.uint32(/* id 4, wireType 2 =*/34).bytes(message.args_json);
                    if (message.args_raw != null && $Object.hasOwnProperty.call(message, "args_raw"))
                        writer.uint32(/* id 5, wireType 2 =*/42).bytes(message.args_raw);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a RpcCall message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.RpcCall
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.RpcCall & gamend.realtime.v1.RpcCall.$Shape} RpcCall
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                RpcCall.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.RpcCall(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.uint32())
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.plugin = value;
                                else
                                    delete message.plugin;
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.fn = value;
                                else
                                    delete message.fn;
                                continue;
                            }
                        case 4: {
                                if (wireType !== 2)
                                    break;
                                message.args_json = reader.bytes();
                                message.args = "args_json";
                                continue;
                            }
                        case 5: {
                                if (wireType !== 2)
                                    break;
                                message.args_raw = reader.bytes();
                                message.args = "args_raw";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a RpcCall message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.RpcCall
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.RpcCall} RpcCall
                 */
                RpcCall.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.RpcCall)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.RpcCall: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.RpcCall();
                    if (object.id != null)
                        if ($Number(object.id) !== 0)
                            message.id = object.id >>> 0;
                    if (object.plugin != null)
                        if (typeof object.plugin !== "string" || object.plugin.length)
                            message.plugin = $String(object.plugin);
                    if (object.fn != null)
                        if (typeof object.fn !== "string" || object.fn.length)
                            message.fn = $String(object.fn);
                    if (object.args_json != null)
                        if (typeof object.args_json === "string")
                            $util.base64.decode(object.args_json, message.args_json = $util.newBuffer($util.base64.length(object.args_json)), 0);
                        else if (object.args_json.length >= 0)
                            message.args_json = object.args_json;
                    if (object.args_raw != null)
                        if (typeof object.args_raw === "string")
                            $util.base64.decode(object.args_raw, message.args_raw = $util.newBuffer($util.base64.length(object.args_raw)), 0);
                        else if (object.args_raw.length >= 0)
                            message.args_raw = object.args_raw;
                    return message;
                };

                /**
                 * Creates a plain object from a RpcCall message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.RpcCall
                 * @static
                 * @param {gamend.realtime.v1.RpcCall} message RpcCall
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                RpcCall.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.id = 0;
                        object.plugin = "";
                        object.fn = "";
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.plugin != null && $Object.hasOwnProperty.call(message, "plugin"))
                        object.plugin = message.plugin;
                    if (message.fn != null && $Object.hasOwnProperty.call(message, "fn"))
                        object.fn = message.fn;
                    if (message.args_json != null && $Object.hasOwnProperty.call(message, "args_json")) {
                        object.args_json = options.bytes === $String ? $util.base64.encode(message.args_json, 0, message.args_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.args_json) : message.args_json;
                        if (options.oneofs)
                            object.args = "args_json";
                    }
                    if (message.args_raw != null && $Object.hasOwnProperty.call(message, "args_raw")) {
                        object.args_raw = options.bytes === $String ? $util.base64.encode(message.args_raw, 0, message.args_raw.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.args_raw) : message.args_raw;
                        if (options.oneofs)
                            object.args = "args_raw";
                    }
                    return object;
                };

                /**
                 * Converts this RpcCall to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.RpcCall
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                RpcCall.prototype.toJSON = function() {
                    return RpcCall.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for RpcCall
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.RpcCall
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                RpcCall.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.RpcCall";
                };

                return RpcCall;
            })();

            v1.RpcReply = (function() {

                /**
                 * Properties of a RpcReply.
                 * @typedef {Object} gamend.realtime.v1.RpcReply.$Properties
                 * @property {number|null} [id] RpcReply id
                 * @property {Uint8Array|null} [data_json] RpcReply data_json
                 * @property {Uint8Array|null} [data_raw] RpcReply data_raw
                 * @property {"data_json"|"data_raw"} [data] RpcReply data
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a RpcReply.
                 * @memberof gamend.realtime.v1
                 * @interface IRpcReply
                 * @augments gamend.realtime.v1.RpcReply.$Properties
                 * @deprecated Use gamend.realtime.v1.RpcReply.$Properties instead.
                 */

                /**
                 * Narrowed shape of a RpcReply.
                 * @typedef {{
                 *   id?: number|null;
                 *   data_json?: Uint8Array|null;
                 *   data_raw?: Uint8Array|null;
                 *   $unknowns?: Array.<Uint8Array>;
                 * } & (
                 *   ({ data?: undefined; data_json?: null; data_raw?: null }|{ data?: "data_json"; data_json: Uint8Array; data_raw?: null }|{ data?: "data_raw"; data_json?: null; data_raw: Uint8Array })
                 * )} gamend.realtime.v1.RpcReply.$Shape
                 */

                /**
                 * Constructs a new RpcReply.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a RpcReply.
                 * @constructor
                 * @param {gamend.realtime.v1.RpcReply.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const RpcReply = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * RpcReply id.
                 * @member {number} id
                 * @memberof gamend.realtime.v1.RpcReply
                 * @instance
                 */
                RpcReply.prototype.id = 0;

                /**
                 * RpcReply data_json.
                 * @member {Uint8Array|null|undefined} data_json
                 * @memberof gamend.realtime.v1.RpcReply
                 * @instance
                 */
                RpcReply.prototype.data_json = null;

                /**
                 * RpcReply data_raw.
                 * @member {Uint8Array|null|undefined} data_raw
                 * @memberof gamend.realtime.v1.RpcReply
                 * @instance
                 */
                RpcReply.prototype.data_raw = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                /**
                 * RpcReply data.
                 * @member {"data_json"|"data_raw"|undefined} data
                 * @memberof gamend.realtime.v1.RpcReply
                 * @instance
                 */
                $Object.defineProperty(RpcReply.prototype, "data", {
                    get: $util.oneOfGetter($oneOfFields = ["data_json", "data_raw"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified RpcReply message. Does not implicitly {@link gamend.realtime.v1.RpcReply.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.RpcReply
                 * @static
                 * @param {gamend.realtime.v1.RpcReply.$Properties} message RpcReply message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                RpcReply.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== 0)
                        writer.uint32(/* id 1, wireType 0 =*/8).uint32(message.id);
                    if (message.data_json != null && $Object.hasOwnProperty.call(message, "data_json"))
                        writer.uint32(/* id 2, wireType 2 =*/18).bytes(message.data_json);
                    if (message.data_raw != null && $Object.hasOwnProperty.call(message, "data_raw"))
                        writer.uint32(/* id 3, wireType 2 =*/26).bytes(message.data_raw);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a RpcReply message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.RpcReply
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.RpcReply & gamend.realtime.v1.RpcReply.$Shape} RpcReply
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                RpcReply.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.RpcReply(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.uint32())
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.data_json = reader.bytes();
                                message.data = "data_json";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.data_raw = reader.bytes();
                                message.data = "data_raw";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a RpcReply message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.RpcReply
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.RpcReply} RpcReply
                 */
                RpcReply.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.RpcReply)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.RpcReply: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.RpcReply();
                    if (object.id != null)
                        if ($Number(object.id) !== 0)
                            message.id = object.id >>> 0;
                    if (object.data_json != null)
                        if (typeof object.data_json === "string")
                            $util.base64.decode(object.data_json, message.data_json = $util.newBuffer($util.base64.length(object.data_json)), 0);
                        else if (object.data_json.length >= 0)
                            message.data_json = object.data_json;
                    if (object.data_raw != null)
                        if (typeof object.data_raw === "string")
                            $util.base64.decode(object.data_raw, message.data_raw = $util.newBuffer($util.base64.length(object.data_raw)), 0);
                        else if (object.data_raw.length >= 0)
                            message.data_raw = object.data_raw;
                    return message;
                };

                /**
                 * Creates a plain object from a RpcReply message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.RpcReply
                 * @static
                 * @param {gamend.realtime.v1.RpcReply} message RpcReply
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                RpcReply.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults)
                        object.id = 0;
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.data_json != null && $Object.hasOwnProperty.call(message, "data_json")) {
                        object.data_json = options.bytes === $String ? $util.base64.encode(message.data_json, 0, message.data_json.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.data_json) : message.data_json;
                        if (options.oneofs)
                            object.data = "data_json";
                    }
                    if (message.data_raw != null && $Object.hasOwnProperty.call(message, "data_raw")) {
                        object.data_raw = options.bytes === $String ? $util.base64.encode(message.data_raw, 0, message.data_raw.length) : options.bytes === $Array ? $Array.prototype.slice.call(message.data_raw) : message.data_raw;
                        if (options.oneofs)
                            object.data = "data_raw";
                    }
                    return object;
                };

                /**
                 * Converts this RpcReply to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.RpcReply
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                RpcReply.prototype.toJSON = function() {
                    return RpcReply.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for RpcReply
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.RpcReply
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                RpcReply.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.RpcReply";
                };

                return RpcReply;
            })();

            v1.RpcError = (function() {

                /**
                 * Properties of a RpcError.
                 * @typedef {Object} gamend.realtime.v1.RpcError.$Properties
                 * @property {number|null} [id] RpcError id
                 * @property {string|null} [error] RpcError error
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a RpcError.
                 * @memberof gamend.realtime.v1
                 * @interface IRpcError
                 * @augments gamend.realtime.v1.RpcError.$Properties
                 * @deprecated Use gamend.realtime.v1.RpcError.$Properties instead.
                 */

                /**
                 * Shape of a RpcError.
                 * @typedef {gamend.realtime.v1.RpcError.$Properties} gamend.realtime.v1.RpcError.$Shape
                 */

                /**
                 * Constructs a new RpcError.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a RpcError.
                 * @constructor
                 * @param {gamend.realtime.v1.RpcError.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const RpcError = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * RpcError id.
                 * @member {number} id
                 * @memberof gamend.realtime.v1.RpcError
                 * @instance
                 */
                RpcError.prototype.id = 0;

                /**
                 * RpcError error.
                 * @member {string} error
                 * @memberof gamend.realtime.v1.RpcError
                 * @instance
                 */
                RpcError.prototype.error = "";

                /**
                 * Encodes the specified RpcError message. Does not implicitly {@link gamend.realtime.v1.RpcError.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.RpcError
                 * @static
                 * @param {gamend.realtime.v1.RpcError.$Properties} message RpcError message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                RpcError.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id") && message.id !== 0)
                        writer.uint32(/* id 1, wireType 0 =*/8).uint32(message.id);
                    if (message.error != null && $Object.hasOwnProperty.call(message, "error") && message.error !== "")
                        writer.uint32(/* id 2, wireType 2 =*/18).string(message.error);
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a RpcError message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.RpcError
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.RpcError & gamend.realtime.v1.RpcError.$Shape} RpcError
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                RpcError.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.RpcError(), value;
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 0)
                                    break;
                                if (value = reader.uint32())
                                    message.id = value;
                                else
                                    delete message.id;
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                if ((value = reader.stringVerify()).length)
                                    message.error = value;
                                else
                                    delete message.error;
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a RpcError message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.RpcError
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.RpcError} RpcError
                 */
                RpcError.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.RpcError)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.RpcError: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.RpcError();
                    if (object.id != null)
                        if ($Number(object.id) !== 0)
                            message.id = object.id >>> 0;
                    if (object.error != null)
                        if (typeof object.error !== "string" || object.error.length)
                            message.error = $String(object.error);
                    return message;
                };

                /**
                 * Creates a plain object from a RpcError message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.RpcError
                 * @static
                 * @param {gamend.realtime.v1.RpcError} message RpcError
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                RpcError.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (options.defaults) {
                        object.id = 0;
                        object.error = "";
                    }
                    if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
                        object.id = message.id;
                    if (message.error != null && $Object.hasOwnProperty.call(message, "error"))
                        object.error = message.error;
                    return object;
                };

                /**
                 * Converts this RpcError to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.RpcError
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                RpcError.prototype.toJSON = function() {
                    return RpcError.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for RpcError
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.RpcError
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                RpcError.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.RpcError";
                };

                return RpcError;
            })();

            v1.RtcEnvelope = (function() {

                /**
                 * Properties of a RtcEnvelope.
                 * @typedef {Object} gamend.realtime.v1.RtcEnvelope.$Properties
                 * @property {gamend.realtime.v1.RpcCall.$Properties|null} [call_hook] RtcEnvelope call_hook
                 * @property {gamend.realtime.v1.RpcReply.$Properties|null} [hook_reply] RtcEnvelope hook_reply
                 * @property {gamend.realtime.v1.RpcError.$Properties|null} [hook_error] RtcEnvelope hook_error
                 * @property {"call_hook"|"hook_reply"|"hook_error"} [msg] RtcEnvelope msg
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */

                /**
                 * Properties of a RtcEnvelope.
                 * @memberof gamend.realtime.v1
                 * @interface IRtcEnvelope
                 * @augments gamend.realtime.v1.RtcEnvelope.$Properties
                 * @deprecated Use gamend.realtime.v1.RtcEnvelope.$Properties instead.
                 */

                /**
                 * Narrowed shape of a RtcEnvelope.
                 * @typedef {{
                 *   call_hook?: gamend.realtime.v1.RpcCall.$Shape|null;
                 *   hook_reply?: gamend.realtime.v1.RpcReply.$Shape|null;
                 *   hook_error?: gamend.realtime.v1.RpcError.$Shape|null;
                 *   $unknowns?: Array.<Uint8Array>;
                 * } & (
                 *   ({ msg?: undefined; call_hook?: null; hook_reply?: null; hook_error?: null }|{ msg?: "call_hook"; call_hook: gamend.realtime.v1.RpcCall.$Shape; hook_reply?: null; hook_error?: null }|{ msg?: "hook_reply"; call_hook?: null; hook_reply: gamend.realtime.v1.RpcReply.$Shape; hook_error?: null }|{ msg?: "hook_error"; call_hook?: null; hook_reply?: null; hook_error: gamend.realtime.v1.RpcError.$Shape })
                 * )} gamend.realtime.v1.RtcEnvelope.$Shape
                 */

                /**
                 * Constructs a new RtcEnvelope.
                 * @memberof gamend.realtime.v1
                 * @classdesc Represents a RtcEnvelope.
                 * @constructor
                 * @param {gamend.realtime.v1.RtcEnvelope.$Properties=} [properties] Properties to set
                 * @property {Array.<Uint8Array>} [$unknowns] Unknown fields preserved while decoding when enabled
                 */
                const RtcEnvelope = function (properties) {
                    if (properties)
                        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
                            if (properties[keys[i]] != null && keys[i] !== "__proto__")
                                this[keys[i]] = properties[keys[i]];
                };

                /**
                 * RtcEnvelope call_hook.
                 * @member {gamend.realtime.v1.RpcCall.$Properties|null|undefined} call_hook
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @instance
                 */
                RtcEnvelope.prototype.call_hook = null;

                /**
                 * RtcEnvelope hook_reply.
                 * @member {gamend.realtime.v1.RpcReply.$Properties|null|undefined} hook_reply
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @instance
                 */
                RtcEnvelope.prototype.hook_reply = null;

                /**
                 * RtcEnvelope hook_error.
                 * @member {gamend.realtime.v1.RpcError.$Properties|null|undefined} hook_error
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @instance
                 */
                RtcEnvelope.prototype.hook_error = null;

                // OneOf field names bound to virtual getters and setters
                let $oneOfFields;

                /**
                 * RtcEnvelope msg.
                 * @member {"call_hook"|"hook_reply"|"hook_error"|undefined} msg
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @instance
                 */
                $Object.defineProperty(RtcEnvelope.prototype, "msg", {
                    get: $util.oneOfGetter($oneOfFields = ["call_hook", "hook_reply", "hook_error"]),
                    set: $util.oneOfSetter($oneOfFields)
                });

                /**
                 * Encodes the specified RtcEnvelope message. Does not implicitly {@link gamend.realtime.v1.RtcEnvelope.verify|verify} messages.
                 * @function encode
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @static
                 * @param {gamend.realtime.v1.RtcEnvelope.$Properties} message RtcEnvelope message or plain object to encode
                 * @param {$protobuf.Writer} [writer] Writer to encode to
                 * @returns {$protobuf.Writer} Writer
                 */
                RtcEnvelope.encode = function (message, writer, _depth) {
                    if (!writer)
                        writer = $Writer.create();
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    if (message.call_hook != null && $Object.hasOwnProperty.call(message, "call_hook"))
                        $root.gamend.realtime.v1.RpcCall.encode(message.call_hook, writer.uint32(/* id 1, wireType 2 =*/10).fork(), _depth + 1).ldelim();
                    if (message.hook_reply != null && $Object.hasOwnProperty.call(message, "hook_reply"))
                        $root.gamend.realtime.v1.RpcReply.encode(message.hook_reply, writer.uint32(/* id 2, wireType 2 =*/18).fork(), _depth + 1).ldelim();
                    if (message.hook_error != null && $Object.hasOwnProperty.call(message, "hook_error"))
                        $root.gamend.realtime.v1.RpcError.encode(message.hook_error, writer.uint32(/* id 3, wireType 2 =*/26).fork(), _depth + 1).ldelim();
                    if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
                        for (let i = 0; i < message.$unknowns.length; ++i)
                            writer.raw(message.$unknowns[i]);
                    return writer;
                };

                /**
                 * Decodes a RtcEnvelope message from the specified reader or buffer.
                 * @function decode
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @static
                 * @param {$protobuf.Reader|Uint8Array} reader Reader or buffer to decode from
                 * @param {number} [length] Message length if known beforehand
                 * @returns {gamend.realtime.v1.RtcEnvelope & gamend.realtime.v1.RtcEnvelope.$Shape} RtcEnvelope
                 * @throws {Error} If the payload is not a reader or valid buffer
                 * @throws {$protobuf.util.ProtocolError} If required fields are missing
                 */
                RtcEnvelope.decode = function (reader, length, _end, _depth, _target) {
                    if (!(reader instanceof $Reader))
                        reader = $Reader.create(reader);
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $Reader.recursionLimit)
                        throw $Error("max depth exceeded");
                    let end = length === $undefined ? reader.len : reader.pos + length, message = _target || new $root.gamend.realtime.v1.RtcEnvelope();
                    while (reader.pos < end) {
                        let start = reader.pos;
                        let tag = reader.tag();
                        if (tag === _end) {
                            _end = $undefined;
                            break;
                        }
                        let wireType = tag & 7;
                        switch (tag >>>= 3) {
                        case 1: {
                                if (wireType !== 2)
                                    break;
                                message.call_hook = $root.gamend.realtime.v1.RpcCall.decode(reader, reader.uint32(), $undefined, _depth + 1, message.call_hook);
                                message.msg = "call_hook";
                                continue;
                            }
                        case 2: {
                                if (wireType !== 2)
                                    break;
                                message.hook_reply = $root.gamend.realtime.v1.RpcReply.decode(reader, reader.uint32(), $undefined, _depth + 1, message.hook_reply);
                                message.msg = "hook_reply";
                                continue;
                            }
                        case 3: {
                                if (wireType !== 2)
                                    break;
                                message.hook_error = $root.gamend.realtime.v1.RpcError.decode(reader, reader.uint32(), $undefined, _depth + 1, message.hook_error);
                                message.msg = "hook_error";
                                continue;
                            }
                        }
                        reader.skipType(wireType, _depth, tag);
                        if (!reader.discardUnknown) {
                            $util.makeProp(message, "$unknowns", false);
                            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                        }
                    }
                    if (_end !== $undefined)
                        throw $Error("missing end group");
                    return message;
                };

                /**
                 * Creates a RtcEnvelope message from a plain object. Also converts values to their respective internal types.
                 * @function fromObject
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @static
                 * @param {Object.<string,*>} object Plain object
                 * @returns {gamend.realtime.v1.RtcEnvelope} RtcEnvelope
                 */
                RtcEnvelope.fromObject = function (object, _depth) {
                    if (object instanceof $root.gamend.realtime.v1.RtcEnvelope)
                        return object;
                    if (!$util.isObject(object))
                        throw $TypeError(".gamend.realtime.v1.RtcEnvelope: object expected");
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let message = new $root.gamend.realtime.v1.RtcEnvelope();
                    if (object.call_hook != null) {
                        if (!$util.isObject(object.call_hook))
                            throw $TypeError(".gamend.realtime.v1.RtcEnvelope.call_hook: object expected");
                        message.call_hook = $root.gamend.realtime.v1.RpcCall.fromObject(object.call_hook, _depth + 1);
                    }
                    if (object.hook_reply != null) {
                        if (!$util.isObject(object.hook_reply))
                            throw $TypeError(".gamend.realtime.v1.RtcEnvelope.hook_reply: object expected");
                        message.hook_reply = $root.gamend.realtime.v1.RpcReply.fromObject(object.hook_reply, _depth + 1);
                    }
                    if (object.hook_error != null) {
                        if (!$util.isObject(object.hook_error))
                            throw $TypeError(".gamend.realtime.v1.RtcEnvelope.hook_error: object expected");
                        message.hook_error = $root.gamend.realtime.v1.RpcError.fromObject(object.hook_error, _depth + 1);
                    }
                    return message;
                };

                /**
                 * Creates a plain object from a RtcEnvelope message. Also converts values to other types if specified.
                 * @function toObject
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @static
                 * @param {gamend.realtime.v1.RtcEnvelope} message RtcEnvelope
                 * @param {$protobuf.IConversionOptions} [options] Conversion options
                 * @returns {Object.<string,*>} Plain object
                 */
                RtcEnvelope.toObject = function (message, options, _depth) {
                    if (!options)
                        options = {};
                    if (_depth === $undefined)
                        _depth = 0;
                    if (_depth > $util.recursionLimit)
                        throw $Error("max depth exceeded");
                    let object = {};
                    if (message.call_hook != null && $Object.hasOwnProperty.call(message, "call_hook")) {
                        object.call_hook = $root.gamend.realtime.v1.RpcCall.toObject(message.call_hook, options, _depth + 1);
                        if (options.oneofs)
                            object.msg = "call_hook";
                    }
                    if (message.hook_reply != null && $Object.hasOwnProperty.call(message, "hook_reply")) {
                        object.hook_reply = $root.gamend.realtime.v1.RpcReply.toObject(message.hook_reply, options, _depth + 1);
                        if (options.oneofs)
                            object.msg = "hook_reply";
                    }
                    if (message.hook_error != null && $Object.hasOwnProperty.call(message, "hook_error")) {
                        object.hook_error = $root.gamend.realtime.v1.RpcError.toObject(message.hook_error, options, _depth + 1);
                        if (options.oneofs)
                            object.msg = "hook_error";
                    }
                    return object;
                };

                /**
                 * Converts this RtcEnvelope to JSON.
                 * @function toJSON
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @instance
                 * @returns {Object.<string,*>} JSON object
                 */
                RtcEnvelope.prototype.toJSON = function() {
                    return RtcEnvelope.toObject(this, $protobuf.util.toJSONOptions);
                };

                /**
                 * Gets the type url for RtcEnvelope
                 * @function getTypeUrl
                 * @memberof gamend.realtime.v1.RtcEnvelope
                 * @static
                 * @param {string} [prefix] Custom type url prefix, defaults to `"type.googleapis.com"`
                 * @returns {string} The type url
                 */
                RtcEnvelope.getTypeUrl = function(prefix) {
                    if (prefix === $undefined)
                        prefix = "type.googleapis.com";
                    return prefix + "/gamend.realtime.v1.RtcEnvelope";
                };

                return RtcEnvelope;
            })();

            return v1;
        })();

        return realtime;
    })();

    return gamend;
})();

export {
  $root as default
};
