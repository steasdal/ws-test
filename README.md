
Grails Websocket Chat Example
=============================

This is a sample Grails app that uses the Spring Websocket Plugin to implement
a rudimentary chat application (with a dash of WebRTC video conferencing throw
in for good measure).  This app does **NOT** make use the Atmosphere plugin.
Messaging on the server side is handled with an annotated service while the
client side is implemented with SockJS/StompJS.  This app is a proof of concept
only and is not intended to be a deployable, production app in any way, shape
or form.