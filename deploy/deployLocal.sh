#!/bin/bash
dart pub get
dart compile exe bin/camilla.dart -o bin/camilla
sudo cp bin/camilla /usr/local/bin/