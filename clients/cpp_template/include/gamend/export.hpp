// What marks the SDK's classes for a shared library.
//
// The CMake build is a static library, and `GAMEND_EXPORT` is empty. A build
// that compiles the SDK into a shared library of its own defines
// `GAMEND_BUILDING` there and `GAMEND_SHARED` wherever it is used: the Unreal
// plugin does, because an editor build links every module as one, and a game
// module calling `gamend::Client` must find its symbols in the plugin's.
#pragma once

#if !defined(GAMEND_EXPORT)
#if defined(GAMEND_BUILDING) || defined(GAMEND_SHARED)
#if defined(_WIN32)
#if defined(GAMEND_BUILDING)
#define GAMEND_EXPORT __declspec(dllexport)
#else
#define GAMEND_EXPORT __declspec(dllimport)
#endif
// The exported classes hold standard-library members, which no library
// exports. Both sides come from one compiler and one standard library, as
// the modules of one editor build do, so that is harmless.
#pragma warning(disable : 4251)
#else
#define GAMEND_EXPORT __attribute__((visibility("default")))
#endif
#else
#define GAMEND_EXPORT
#endif
#endif
