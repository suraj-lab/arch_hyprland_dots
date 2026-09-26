#!/usr/bin/env python3
"""A fake MPRIS player for offline shell tests, on whatever session bus is set.

Usage: fake_mpris.py <0|1> <art.png>. Run one process per player (each needs its own
connection for /org/mpris/MediaPlayer2), and only ever on a private bus
(dbus-run-session), never on the real session. 0 = Spotify, paused (so "Spotify first"
must not depend on playing); 1 = Firefox playing a YouTube video. Prints "ready".
"""
import sys
from gi.repository import Gio, GLib

XML = """<node>
 <interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/><method name="Quit"/>
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
  <property name="CanQuit" type="b" access="read"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/>
  <property name="SupportedMimeTypes" type="as" access="read"/>
 </interface>
 <interface name="org.mpris.MediaPlayer2.Player">
  <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="Play"/>
  <method name="PlayPause"/><method name="Stop"/>
  <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
  <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/><arg name="Position" type="x" direction="in"/></method>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Position" type="x" access="read"/>
  <property name="Rate" type="d" access="read"/>
  <property name="Volume" type="d" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
 </interface>
</node>"""

PLAYERS = [
    ("org.mpris.MediaPlayer2.spotify", "Spotify", "spotify", "Paused",
     "Midnight City", ["M83"], "Hurry Up, We're Dreaming", 243, 61),
    ("org.mpris.MediaPlayer2.firefox.instance_1_42", "Mozilla Firefox", "firefox", "Playing",
     "How Wayland compositors work - YouTube", ["Some Channel"], "", 1325, 540),
]


def serve(name, identity, entry, status, title, artists, album, length, position, art):
    metadata = {
        "mpris:trackid": GLib.Variant("o", "/track/1"),
        "xesam:title": GLib.Variant("s", title),
        "xesam:artist": GLib.Variant("as", artists),
        "xesam:album": GLib.Variant("s", album),
        "mpris:length": GLib.Variant("x", length * 1_000_000),
        "mpris:artUrl": GLib.Variant("s", "file://" + art),
    }
    props = {
        "Identity": GLib.Variant("s", identity), "DesktopEntry": GLib.Variant("s", entry),
        "CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
        "HasTrackList": GLib.Variant("b", False), "SupportedUriSchemes": GLib.Variant("as", []),
        "SupportedMimeTypes": GLib.Variant("as", []), "PlaybackStatus": GLib.Variant("s", status),
        "Metadata": GLib.Variant("a{sv}", metadata), "Position": GLib.Variant("x", position * 1_000_000),
        "Rate": GLib.Variant("d", 1.0), "Volume": GLib.Variant("d", 1.0),
        "CanGoNext": GLib.Variant("b", True), "CanGoPrevious": GLib.Variant("b", True),
        "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
        "CanSeek": GLib.Variant("b", True), "CanControl": GLib.Variant("b", True),
    }

    def on_bus(connection, _name):
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        for iface in info.interfaces:
            connection.register_object(
                "/org/mpris/MediaPlayer2", iface,
                lambda *a: a[-1].return_value(None),               # methods: accept, no-op
                lambda _c, _s, _p, _i, prop: props[prop],          # property getter
                None)

    return Gio.bus_own_name(Gio.BusType.SESSION, name, Gio.BusNameOwnerFlags.NONE,
                            on_bus, lambda *a: owned.add(a[1]), None)


owned = set()
serve(*PLAYERS[int(sys.argv[1])], sys.argv[2])
loop = GLib.MainLoop()


def check():
    if owned:
        print("ready", flush=True)
        return False
    return True


GLib.timeout_add(50, check)
loop.run()
