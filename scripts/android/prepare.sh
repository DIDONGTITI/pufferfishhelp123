#!/bin/sh

# libsimplex.so and libsupport.so binaries should be in ~/Downloads folder in their directories based on archive name
mkdir -p ./apps/android/app/src/main/cpp/libs/arm64-v8a/
rm ./apps/android/app/src/main/cpp/libs/arm64-v8a/*
cp ~/Downloads/pkg-aarch64-android-libsupport/libsupport.so ./apps/android/app/src/main/cpp/libs/arm64-v8a/
cp ~/Downloads/pkg-aarch64-android-libsimplex/libsimplex.so ./apps/android/app/src/main/cpp/libs/arm64-v8a/

mkdir -p ./apps/android/app/src/main/cpp/libs/armeabi-v7a/
rm ./apps/android/app/src/main/cpp/libs/armeabi-v7a/*
cp ~/Downloads/pkg-armv7a-android-libsupport/libsupport.so ./apps/android/app/src/main/cpp/libs/armeabi-v7a/
cp ~/Downloads/pkg-armv7a-android-libsimplex/libsimplex.so ./apps/android/app/src/main/cpp/libs/armeabi-v7a/
