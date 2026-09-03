# METEOR
<div align="center">
  <img src="logo-fill.png" alt="Meteor Logo Image" title="This is a sample image." width="200">

  Hyperpad **.tap** player made with Godot 4.7

<p align="center">
  <img src="docs/image.png" width="350">&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/image2.png" width="350">
</p>
<p align="center">
  <img src="docs/image3.png" width="350">&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/image4.png" width="350">
</p>
</div>

> Note: This project only runs .tap files. It is not an alternative to the [Hyperpad Game Engine](https://www.hyperpad.com/)

Meteor is a Hyperpad .tap player similar to the [Hyperpad Hub Player](https://apps.apple.com/us/app/hyperpad-hub/id1484881474?platform=ipad) on IOS and IpadOS except built using Godot to give you the ability to play hyperpad games on Windows/Linux. All logic code will eventually  be converted into C#

- Extracts sqlite data from .tap and converts it to JSON.
- Extracts image, audio, ttfont, and bitmap font assets.

> [!WARNING]
> This project is still in early development, so features are going to be missing.

#### Todo

<div align="center">
  <img src="https://raw.githubusercontent.com/Dangerbites/METEOR/main/docs/progress.svg" alt="Behaviors Progress">
</div>

- [x] Empty Objects
- [x] Life Objects
- [x] Hyperpad Camera
- [x] Health Bar Objects
- [x] Joystick Objects
- [x] Graphic Objects
- [x] Layers
    - [x] z-order
    - [x] normal layers
    - [x] UI layers
- [x] tags
- [x] collision shapes
  - [x] Graphic Objects
  - [x] Empty Objects
  - [ ] LifeObjects
  - [ ] HelathBars
  - [ ] Joystick
  - [x] Labels
- [ ] Behaviors
  - [ ] Active State
  - [x] Add To Score
  - [ ] Add to Health Bar
  - [ ] Add to Life Indicator
  - [ ] Ad Clicked
  - [ ] Air Resistance
  - [ ] Alert
  - [ ] Apply Force
  - [ ] Apply Torque
  - [ ] Array
  - [ ] Authenticate OAuth
  - [ ] Battery Status
  - [ ] Became Idle
  - [x] Behavior Bundle
  - [x] Behaviour Off
  - [x] Behaviour On (Needs Testing)
  - [ ] Bitwise Operation
  - [ ] Boolean
  - [ ] Box Container
  - [ ] Broadcast Message
  - [x] Broadcast Message v1.19
  - [ ] Calculate Direction
  - [ ] Calculate Distance
  - [ ] Clamp Value
  - [ ] Clipboard
  - [ ] Close Overlay
  - [x] Combine Text
  - [x] Comment
  - [ ] Connect to Socket
  - [x] Collided / Started Colliding
  - [x] Collision Event
    - [x] While Colliding
    - [x] Started Colliding (Needs to be tested)
    - [x] Stopped Colliding (Needs to be tested)
  - [ ] Count Down
  - [ ] Create Collision
  - [x] Destroy Object
  - [ ] Detach Object
  - [ ] Device Identifier
  - [ ] Dictionary
  - [ ] Disable Object
  - [ ] Delete from File
  - [ ] Draw
  - [ ] Drag & Drop
  - [ ] Dragged Finger
  - [ ] Edit Text Event
  - [ ] Edit Text Field
  - [ ] Emit to Socket
  - [ ] Enable Object
  - [ ] Execute Behaviour
  - [x] Execute Sequence
    - [x] Sequential
    - [ ] Random (Implimented I think? Should still be tested)
  - [ ] Falling State
  - [x] Frame Event
    - Unsure, should check bugs for it
  - [ ] Get Array Count
  - [ ] Get Array Value
  - [ ] Get Attribute
  - [ ] Get Background
  - [ ] Get Bounding Box
  - [ ] Get Color
  - [ ] Get Dictionary Value
  - [ ] Get Graphic Flip
  - [ ] Get Gravity
  - [ ] Get Health Bar
  - [x] Get Label
  - [ ] Get Life Indicator
  - [ ] Get Mouse Position
  - [ ] Get Music Settings
  - [ ] Get Noise Value
  - [ ] Get OAuth Credentials
  - [ ] Get Object
  - [ ] Get Objects By Tag
  - [ ] Get Physics Properties
  - [ ] Get Pixel
  - [ ] Get Position
  - [ ] Get Rotation
  - [ ] Get Rotational Velocity
  - [x] Get Screen
  - [x] Get Scale
  - [ ] Get Skew
  - [ ] Get Socket Status
  - [ ] Get Time
  - [ ] Get Velocity
  - [ ] Get Z Order
  - [x] Hide Graphic
  - [ ] Hit by Bullet
  - [ ] HitPoint Test
  - [ ] HTTP Request
  - [x] If
  - [ ] Ignore Bullets
  - [ ] Ignore Collisions
  - [ ] Ignore Object's Bullets
  - [ ] Indicator Event
  - [ ] Interpolate Value
  - [ ] Is Intersecting
  - [ ] Joystick Controlled
  - [ ] Joystick Down
  - [ ] Joystick Input
  - [ ] Joystick Left
  - [ ] Joystick Right
  - [ ] Joystick Up
  - [ ] Jump with Button
  - [ ] Keyboard Event
  - [ ] Keyboard Shortcut
  - [ ] Load Image
  - [x] Load Scene
    - [ ] Transitions
      - [x] none 
  - [ ] Load Overlay
  - [ ] Load Previous Scene
  - [ ] Load from File
  - [ ] Lock Rotation
  - [ ] Loop
  - [ ] Make Passable
  - [ ] Make Physics
  - [ ] Make Scenery
  - [ ] Make Wall
  - [x] Multiply Values
  - [ ] Add Values
  - [x] Divide Values (needs testing)
  - [ ] Modulus
  - [x] Subtract Values (needs testing)
  - [ ] Square Root
  - [ ] Math Expression
  - [ ] Math Function
  - [ ] Maximum
  - [ ] Minimum
  - [ ] Modify Array
  - [ ] Modify Dictionary
  - [ ] Modify Save File
  - [ ] Modify Tags
  - [ ] Mouse Event
  - [ ] Movable Platform
  - [x] Move By
  - [ ] Move to Layer
  - [ ] Move to Object
  - [x] Move To Point
  - [ ] Moving State
  - [ ] Noise Map
  - [ ] Open URL
  - [ ] Passable Platform
  - [ ] Patrol
  - [x] Play Sound v1.21
  - [x] Play Music v1.21
  - [ ] Pause Music
  - [ ] Pivot Attach
  - [ ] Post to Facebook
  - [ ] Preload Scene
  - [ ] Propel Object
  - [ ] Quit Project
  - [x] Random Number
  - [ ] Raycast Test
  - [ ] Receive Message
  - [x] Receive Message v1.19
  - [ ] Remove OAuth Credentials
  - [ ] Render Texture
  - [ ] Restart Scene
  - [ ] Rope Attach
  - [ ] Rotate By
  - [ ] Rotate to Angle
  - [ ] Rotate to Object
  - [ ] Round Number
  - [ ] Save to File
  - [x] Scale By
  - [x] Scale To
  - [x] Screen Follow
  - [x] Screen To Object
  - [ ] Screen to Point
  - [ ] Set Attribute
  - [ ] Set Background
  - [ ] Set Background Color
  - [ ] Set Behavior State
  - [ ] Set Blending Mode
  - [ ] Set Bounce
  - [x] Set Color
  - [ ] Set Cursor Style
  - [ ] Set Friction
  - [x] Set Graphic v1.26
  - [ ] Set Graphic Flip
  - [ ] Set Gravity
  - [ ] Set Health Bar
  - [x] Set Label
  - [ ] Set Layer Visibility
  - [ ] Set Life Indicator
  - [ ] Set Mass
  - [ ] Set Music Settings
  - [ ] Set Physics Mode
  - [ ] Set Physics Property
  - [ ] Set Rotational Velocity
  - [ ] Set Sound Settings
  - [ ] Set Time Scale
  - [ ] Set Visibility
  - [x] Set Z Order
  - [x] Shake Screen / Shake Camera v1_24
  - [ ] Share
  - [ ] Shoot
  - [ ] Shoot with Button
  - [ ] Show Graphic
  - [x] Show Layer v1.26
  - [ ] Skew By
  - [ ] Skew To
  - [ ] Socket Event
  - [ ] Socket.io Client
  - [ ] Sort Array
  - [ ] Sort by Distance
  - [x] Spawn On Area
  - [ ] Spawn on Object
  - [ ] Spring Attach
  - [ ] Start Trail
  - [x] Started Touching
  - [ ] Started Falling
  - [ ] Stop Visual Effects
  - [ ] Stopped Falling
  - [ ] Stopped Moving
  - [ ] Stopped Touching
  - [ ] Swipe Down
  - [ ] Swipe Gesture
  - [ ] Swipe Left
  - [ ] Swipe Right
  - [ ] Swipe Up
  - [ ] Text Bubble
  - [ ] Text Length
  - [ ] Text Operation
  - [ ] Tilt Controlled
  - [ ] Tilt Down
  - [ ] Tilt Left
  - [ ] Tilt Right
  - [ ] Tilt Sensor
  - [ ] Tilt Up
  - [x] Timer
  - [x] Timer v1.33
  - [ ] Track Event
  - [ ] Trigger Ad
  - [ ] Trim Text
  - [ ] Tweet
  - [x] Turn Physics On
  - [ ] Unload Scene
  - [ ] Value
  - [x] Wait
  - [ ] Weld Attach
  - [x] While Colliding
  - [ ] While Moving
  - [ ] While Touching
  - [ ] Wrap Around Screen
  - [x] Zoom Screen

## Debugging
To open the behavior interpreter debugging window press `TAB` to activate it

This is used to check if behaviors are being ran properly and to debug. Letting you get the behaviors `TAG UUID` and copy its function name for implimentation.

`F2` Displays FPS

## Developer Console
Meteor includes a developer console for debugging and extra useful features. Press `~` to activate it

**Commands List**
```
loadScene <Scene Name : String>
getSceneNames <Doesnt need arguments : Void>
```

## Prerequisites
If youd like to contribute to Meteor you need to have Python installed with these packages as well as Godot 4.7.
```
import av
import base64
import json
import os
import plistlib
import re
import sqlite3
import tempfile
import zipfile
from plistlib import UID
```