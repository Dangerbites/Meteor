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

- [x] Empty Objects
- [x] Life Objects
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
  - [ ] Labels
- [ ] Behaviors
  - [ ] Array
  - [ ] Authenticate OAuth
  - [ ] Battery Status
  - [ ] Behavior Bundle
  - [ ] Behaviour Off
  - [x] Behaviour On (Needs Testing)
  - [ ] Bitwise Operation
  - [ ] Boolean
  - [ ] Box Container
  - [ ] Broadcast Message
  - [ ] Calculate Direction
  - [ ] Calculate Distance
  - [ ] Clamp Value
  - [ ] Clipboard
  - [ ] Combine Text
  - [ ] Comment
  - [ ] Connect to Socket
  - [x] Collision Event
    - [x] While Colliding
    - [x] Started Colliding (Needs to be tested)
    - [x] Stopped Colliding (Needs to be tested)
  - [ ] Create Collision
  - [x] Destroy Object
  - [ ] Delete from File
  - [ ] Device Identifier
  - [ ] Dictionary
  - [ ] Draw
  - [ ] Edit Text Event
  - [ ] Edit Text Field
  - [ ] Emit to Socket
  - [ ] Execute Behaviour
  - [x] Execute Sequence
    - [x] Sequential
    - [ ] Random (Implimented I think? Should still be tested)
  - [x] Frame Event
    - Unsure, should check bugs for it
  - [ ] Get Array Count
  - [ ] Get Array Value
  - [ ] Get Background
  - [ ] Get Bounding Box
  - [ ] Get Dictionary Value
  - [ ] Get Life Indicator
  - [ ] Get Mouse Position
  - [ ] Get Noise Value
  - [ ] Get OAuth Credentials
  - [ ] Get Object
  - [ ] Get Objects By Tag
  - [ ] Get Pixel
  - [ ] Get Socket Status
  - [ ] Get Time
  - [ ] HTTP Request
  - [ ] HitPoint Test
  - [ ] If
  - [ ] Indicator Event
  - [ ] Interpolate Value
  - [ ] Is Intersecting
  - [ ] Keyboard Event
  - [ ] Keyboard Shortcut
  - [ ] Load Image
  - [x] Load Scene
    - [ ] Transitions
      - [x] none 
  - [ ] Load from File
  - [ ] Loop
  - [ ] Math Expression
  - [ ] Math Function
  - [ ] Maximum
  - [ ] Minimum
  - [ ] Modify Array
  - [ ] Modify Dictionary
  - [ ] Modify Save File
  - [ ] Modify Tags
  - [ ] Mouse Event
  - [x] Move By
  - [x] Move To Point
  - [ ] Noise Map
  - [ ] Open URL
  - [ ] Post to Facebook
  - [x] Play Sound v1.21
  - [x] Play Music v1.21
  - [ ] Quit Project
  - [ ] Random Number
  - [ ] Raycast Test
  - [ ] Receive Message
  - [ ] Remove OAuth Credentials
  - [ ] Render Texture
  - [ ] Round Number
  - [ ] Save to File
  - [x] Scale By
  - [ ] Set Background
  - [ ] Set Background Color
  - [ ] Set Behavior State
  - [ ] Set Cursor Style
  - [x] Set Color
  - [ ] Set Music Settings
  - [ ] Set Physics Mode
  - [ ] Set Physics Property
  - [ ] Set Sound Settings
  - [ ] Set Visibility
  - [ ] Share
  - [x] Show Layer v1.26
  - [ ] Socket Event
  - [ ] Socket.io Client
  - [ ] Sort Array
  - [ ] Sort by Distance
  - [ ] Start Trail
  - [x] Started Touching
  - [ ] Stop Visual Effects
  - [ ] Subtract Values
  - [ ] Swipe Gesture
  - [ ] Text Length
  - [ ] Text Operation
  - [x] Timer
  - [x] Timer v1.33
  - [ ] Track Event
  - [ ] Trim Text
  - [ ] Tweet
  - [ ] Value
  - [x] Wait
  - [x] While Colliding

## Debugging
To open the behavior interpreter debugging window press `TAB` to activate it

This is used to check if behaviors are being ran properly and to debug. Letting you get the behaviors `TAG UUID` and copy its function name for implimentation.

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
