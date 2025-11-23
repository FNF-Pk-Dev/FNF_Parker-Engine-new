package discord_rpc;

import cpp.Callable;
import cpp.ConstCharStar;
import cpp.ConstPointer;
import cpp.Function;
import cpp.RawConstPointer;
import cpp.Star;

// Local copy to avoid upstream warnings until the haxelib is updated.
class DiscordRpc
{
    /** Called once Discord has connected and is ready to start. */
    public static var onReady:Void->Void;

    /** Called when discord has disconnected the program. Int is the error code, String is the message. */
    public static var onDisconnected:Int->String->Void;

    /** Called when an error occurred. Int is the error code, String is the message. */
    public static var onError:Int->String->Void;

    /** Called when the user has joined a game through discord. String is the join secret. */
    public static var onJoin:String->Void;

    /** Called when the user has spectated a game through discord. String is the spectate secret. */
    public static var onSpectate:String->Void;

    /** Called when the user has received a join request. */
    public static var onRequest:JoinRequest->Void;

    /** Attempts to connect to discord and initialize itself. */
    public static function start(options:DiscordStartOptions)
    {
        onReady = options.onReady;
        onDisconnected = options.onDisconnected;
        onError = options.onError;
        onJoin = options.onJoin;
        onSpectate = options.onSpectate;
        onRequest = options.onRequest;
        DiscordRpcExterns.init(options.clientID, options.steamAppID);
    }

    /** Call this to process any callbacks. */
    public static function process()
    {
        DiscordRpcExterns.process();
    }

    /** Respond to a join request. */
    public static function respond(userID:String, response:Reply)
    {
        DiscordRpcExterns.respond(userID, response);
    }

    /** Set the rich presence for discord. */
    public static function presence(options:DiscordPresenceOptions)
    {
        DiscordRpcExterns.setPresence(
            options.state, options.details,
            options.startTimestamp, options.endTimestamp,
            options.largeImageKey, options.largeImageText,
            options.smallImageKey, options.smallImageText,
            options.partyID, options.partySize, options.partyMax,
            options.matchSecret, options.joinSecret, options.spectateSecret,
            options.instance
        );
    }

    /** Stops rich presence content from showing. */
    public static function shutdown()
    {
        DiscordRpcExterns.shutdown();
    }
}

@:keep
@:include('linc_discord_rpc.h')
#if !display
@:build(linc.Linc.touch())
@:build(linc.Linc.xml('discord_rpc'))
#end
private extern class DiscordRpcExterns
{
    @:native('linc::discord_rpc::init')
    private static function _init(clientID:String, steamAppID:String, onReady:VoidCallback, onDisconnected:ErrorCallback, onError:ErrorCallback, onJoin:SecretCallback, onSpectate:SecretCallback, onRequest:RequestCallback):Void;

    static inline function init(clientID:String, ?steamAppID:String):Void
    {
        _init(
            clientID,
            steamAppID,
            Function.fromStaticFunction(_onReady),
            Function.fromStaticFunction(_onDisconnected),
            Function.fromStaticFunction(_onError),
            Function.fromStaticFunction(_onJoin),
            Function.fromStaticFunction(_onSpectate),
            Function.fromStaticFunction(_onRequest)
        );
    }

    @:native('linc::discord_rpc::process')
    public static function process():Void;

    @:native('linc::discord_rpc::respond')
    public static function respond(userID:String, reply:Int):Void;

    @:native('linc::discord_rpc::update_presence')
    public static function setPresence(
        state:String, details:String,
        startTimestamp:cpp.Int64, endTimestamp:cpp.Int64,
        largeImageKey:String, largeImageText:String,
        smallImageKey:String, smallImageText:String,
        partyID:String, partySize:Int, partyMax:Int,
        matchSecret:String, joinSecret:String, spectateSecret:String,
        instance:cpp.Int8
    ):Void;

    @:native('linc::discord_rpc::shutdown')
    public static function shutdown():Void;

    private static inline function _onReady():Void
    {
        if (DiscordRpc.onReady != null) DiscordRpc.onReady();
    }

    private static inline function _onDisconnected(errorCode:Int, message:ConstCharStar):Void
    {
        if (DiscordRpc.onDisconnected != null) DiscordRpc.onDisconnected(errorCode, message);
    }

    private static inline function _onError(errorCode:Int, message:ConstCharStar):Void
    {
        if (DiscordRpc.onError != null) DiscordRpc.onError(errorCode, message);
    }

    private static inline function _onJoin(secret:ConstCharStar):Void
    {
        if (DiscordRpc.onJoin != null) DiscordRpc.onJoin(secret);
    }

    private static inline function _onSpectate(secret:ConstCharStar):Void
    {
        if (DiscordRpc.onSpectate != null) DiscordRpc.onSpectate(secret);
    }

    private static inline function _onRequest(data:RawConstPointer<JoinRequest>):Void
    {
        var ptr:cpp.Star<JoinRequest> = cast data;
        if (DiscordRpc.onRequest != null) DiscordRpc.onRequest(ptr);
    }
}

@:include('linc_discord_rpc.h')
@:native('DiscordJoinRequest')
@:structAccess
@:unreflective
extern class JoinRequest
{
    public var userId:String;
    public var username:String;
    public var discriminator:String;
    public var avatar:String;
}

typedef VoidCallback = Callable<Void->Void>;
typedef ErrorCallback = Callable<Int->ConstCharStar->Void>;
typedef SecretCallback = Callable<ConstCharStar->Void>;
typedef RequestCallback = Callable<RawConstPointer<JoinRequest>->Void>;

typedef DiscordStartOptions = {
    var clientID:String;
    @:optional var steamAppID:String;
    @:optional var onReady:Void->Void;
    @:optional var onDisconnected:Int->String->Void;
    @:optional var onError:Int->String->Void;
    @:optional var onJoin:String->Void;
    @:optional var onSpectate:String->Void;
    @:optional var onRequest:JoinRequest->Void;
}

typedef DiscordPresenceOptions = {
    @:optional var state:String;
    @:optional var details:String;
    @:optional var startTimestamp:Int;
    @:optional var endTimestamp:Int;
    @:optional var largeImageKey:String;
    @:optional var largeImageText:String;
    @:optional var smallImageKey:String;
    @:optional var smallImageText:String;
    @:optional var partyID:String;
    @:optional var partySize:Int;
    @:optional var partyMax:Int;
    @:optional var matchSecret:String;
    @:optional var spectateSecret:String;
    @:optional var joinSecret:String;
    @:optional var instance:Int;
}

enum abstract Reply(Int) from Int to Int
{
    var No = 0;
    var Yes = 1;
    var ignore = 2;
}
