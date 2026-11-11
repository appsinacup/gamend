# The Gamend C++ SDK.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build
#
# In a game: add_subdirectory(cpp_sdk), FetchContent, or
# find_package(gamend) after `cmake --install`, then link gamend::gamend.
# Dependencies come from find_package when the host already has them, and
# from FetchContent otherwise.
cmake_minimum_required(VERSION 3.20)

# The release CI stamps into version.hpp; a local generation says "dev".
file(STRINGS include/gamend/version.hpp gamend_version_line REGEX "#define GAMEND_VERSION ")
string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" gamend_version "${gamend_version_line}")
if(NOT gamend_version)
  set(gamend_version 0.0.0)
endif()
project(gamend VERSION ${gamend_version} LANGUAGES CXX)

# Extracted dependencies get the time of extraction, so a changed URL rebuilds.
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

set(GAMEND_TOP_LEVEL OFF)
if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
  set(GAMEND_TOP_LEVEL ON)
endif()

option(GAMEND_WITH_CURL "Build the libcurl HTTP transport" ON)
option(GAMEND_WITH_IXWEBSOCKET "Build the IXWebSocket transport" ON)
option(GAMEND_IXWEBSOCKET_TLS "Build IXWebSocket with TLS (wss://)" ON)
option(GAMEND_WITH_WEBRTC "Build the libdatachannel WebRTC peer" OFF)
option(GAMEND_BUILD_TESTS "Build the unit tests" ${GAMEND_TOP_LEVEL})
option(GAMEND_BUILD_EXAMPLES "Build the examples" ${GAMEND_TOP_LEVEL})
option(GAMEND_WARNINGS_AS_ERRORS "Fail the build on a warning in the SDK's own code" OFF)
option(GAMEND_INSTALL "Install the SDK and a CMake package for find_package(gamend)" ${GAMEND_TOP_LEVEL})

include(FetchContent)
include(GNUInstallDirs)
find_package(Threads REQUIRED)

find_package(nlohmann_json 3.11 CONFIG QUIET)
if(NOT nlohmann_json_FOUND)
  FetchContent_Declare(nlohmann_json
    URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
    URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa)
  # The installed SDK's headers include it, so it installs alongside.
  set(JSON_Install ${GAMEND_INSTALL} CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(nlohmann_json)
  # A dependency's headers, not ours: warnings in them are not the SDK's.
  set_property(TARGET nlohmann_json APPEND PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
    $<TARGET_PROPERTY:nlohmann_json,INTERFACE_INCLUDE_DIRECTORIES>)
endif()

# The core builds without exceptions and without RTTI, as Unreal does by
# default, and warning-free. Applied to the SDK's own sources only.
function(gamend_strict target)
  set_target_properties(${target} PROPERTIES CXX_EXTENSIONS OFF)
  if(MSVC)
    # /bigobj: the generated API and models are large translation units.
    target_compile_options(${target} PRIVATE /W4 /GR- /EHs-c- /bigobj /utf-8)
    target_compile_definitions(${target} PRIVATE _HAS_EXCEPTIONS=0)
    if(GAMEND_WARNINGS_AS_ERRORS)
      target_compile_options(${target} PRIVATE /WX)
    endif()
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -fno-exceptions -fno-rtti)
    if(GAMEND_WARNINGS_AS_ERRORS)
      target_compile_options(${target} PRIVATE -Werror)
    endif()
  endif()
endfunction()

add_library(gamend
  src/api.cpp
  src/auth.cpp
  src/client.cpp
  src/kv.cpp
  src/loop.cpp
  src/models.cpp
  src/phoenix.cpp
  src/proto.cpp
  src/proto_schema.cpp
  src/query.cpp
  src/presence.cpp
  src/realtime.cpp
  src/rest.cpp
  src/session.cpp
  src/webrtc.cpp)
add_library(gamend::gamend ALIAS gamend)
target_include_directories(gamend
  PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
         $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_features(gamend PUBLIC cxx_std_17)
target_link_libraries(gamend PUBLIC nlohmann_json::nlohmann_json Threads::Threads)
gamend_strict(gamend)

if(GAMEND_WITH_CURL)
  find_package(CURL QUIET)
  if(NOT CURL_FOUND)
    # Only HTTP(S), statically, over the platform's own TLS where there is one.
    set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(HTTP_ONLY ON CACHE BOOL "" FORCE)
    set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
    set(CURL_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
    set(CURL_ZLIB OFF CACHE STRING "" FORCE)
    set(CURL_BROTLI OFF CACHE STRING "" FORCE)
    set(CURL_ZSTD OFF CACHE STRING "" FORCE)
    set(USE_NGHTTP2 OFF CACHE BOOL "" FORCE)
    set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
    if(WIN32)
      set(CURL_USE_SCHANNEL ON CACHE BOOL "" FORCE)
    endif()
    FetchContent_Declare(curl
      URL https://github.com/curl/curl/releases/download/curl-8_23_0/curl-8.23.0.tar.xz
      URL_HASH SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5)
    FetchContent_MakeAvailable(curl)
  endif()
  target_sources(gamend PRIVATE src/curl_transport.cpp)
  target_link_libraries(gamend PRIVATE CURL::libcurl)
  target_compile_definitions(gamend PUBLIC GAMEND_WITH_CURL=1)
endif()

set(GAMEND_FETCHED_MBEDTLS OFF)
if(GAMEND_WITH_IXWEBSOCKET)
  find_package(ixwebsocket CONFIG QUIET)
  if(NOT ixwebsocket_FOUND)
    set(USE_TLS ${GAMEND_IXWEBSOCKET_TLS} CACHE BOOL "" FORCE)
    set(USE_ZLIB OFF CACHE BOOL "" FORCE)
    set(IXWEBSOCKET_INSTALL ${GAMEND_INSTALL} CACHE BOOL "" FORCE)

    # IXWebSocket speaks TLS through OpenSSL, mbedTLS or (on Apple) Secure
    # Transport, never Schannel: on Windows it asks for mbedTLS, which Windows
    # does not ship, and the build stops at `Could NOT find MbedTLS`. Take
    # OpenSSL when this build has one, and otherwise build mbedTLS here, so
    # `wss://` works with nothing installed by hand.
    if(GAMEND_IXWEBSOCKET_TLS AND NOT USE_OPEN_SSL AND NOT USE_SECURE_TRANSPORT)
      if(NOT USE_MBED_TLS AND WIN32)
        find_package(OpenSSL QUIET)
        if(OpenSSL_FOUND)
          set(USE_OPEN_SSL ON CACHE BOOL "" FORCE)
        else()
          set(USE_MBED_TLS ON CACHE BOOL "" FORCE)
        endif()
      endif()
      if(USE_MBED_TLS)
        # What IXWebSocket's own FindMbedTLS looks for; when it is there, let
        # it find that one.
        find_path(GAMEND_MBEDTLS_INCLUDE_DIR mbedtls/ssl.h)
        find_library(GAMEND_MBEDTLS_LIBRARY NAMES mbedtls libmbedtls)
        if(NOT GAMEND_MBEDTLS_INCLUDE_DIR OR NOT GAMEND_MBEDTLS_LIBRARY)
          set(GAMEND_FETCHED_MBEDTLS ON)
        endif()
      endif()
    endif()

    if(GAMEND_FETCHED_MBEDTLS)
      set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
      set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
      # Its CMake package installs with the SDK, so a game that installs the
      # SDK can find_package(gamend) and get this back.
      if(GAMEND_INSTALL)
        set(DISABLE_PACKAGE_CONFIG_AND_INSTALL OFF CACHE BOOL "" FORCE)
      else()
        set(DISABLE_PACKAGE_CONFIG_AND_INSTALL ON CACHE BOOL "" FORCE)
      endif()
      FetchContent_Declare(mbedtls
        URL https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2
        URL_HASH SHA256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6)
      FetchContent_MakeAvailable(mbedtls)
      # What IXWebSocket's FindMbedTLS would have set, so it takes this one
      # instead of looking for an installed copy.
      set(MBEDTLS_FOUND TRUE)
      set(MBEDTLS_INCLUDE_DIRS ${mbedtls_SOURCE_DIR}/include)
      set(MBEDTLS_LIBRARIES mbedtls mbedx509 mbedcrypto)
    endif()

    FetchContent_Declare(ixwebsocket
      URL https://github.com/machinezone/IXWebSocket/archive/refs/tags/v12.1.0.tar.gz
      URL_HASH SHA256=55f3a5d3a1a2c5f19d737c24e6aced28d1200f8f5deb45ecd8e5d46f765b5288)
    FetchContent_MakeAvailable(ixwebsocket)

    if(GAMEND_FETCHED_MBEDTLS)
      # The 3.x API, which IXWebSocket only defines when it found mbedTLS
      # itself. Its headers are a dependency's, not ours.
      target_compile_definitions(ixwebsocket PRIVATE IXWEBSOCKET_USE_MBED_TLS_MIN_VERSION_3)
      set_property(TARGET ixwebsocket APPEND PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
        ${MBEDTLS_INCLUDE_DIRS})
    endif()
  endif()
  target_sources(gamend PRIVATE src/ix_websocket_transport.cpp)
  target_link_libraries(gamend PRIVATE ixwebsocket::ixwebsocket)
  target_compile_definitions(gamend PUBLIC GAMEND_WITH_IXWEBSOCKET=1)
endif()

if(GAMEND_WITH_WEBRTC)
  find_package(LibDataChannel CONFIG QUIET)
  if(NOT LibDataChannel_FOUND)
    # Homebrew keeps OpenSSL out of the default search path.
    if(APPLE AND NOT OPENSSL_ROOT_DIR AND EXISTS /opt/homebrew/opt/openssl@3)
      set(OPENSSL_ROOT_DIR /opt/homebrew/opt/openssl@3)
    endif()
    set(NO_MEDIA ON CACHE BOOL "" FORCE)
    set(NO_WEBSOCKET ON CACHE BOOL "" FORCE)
    set(NO_EXAMPLES ON CACHE BOOL "" FORCE)
    set(NO_TESTS ON CACHE BOOL "" FORCE)
    FetchContent_Declare(libdatachannel
      GIT_REPOSITORY https://github.com/paullouisageneau/libdatachannel.git
      GIT_TAG v0.24.6
      GIT_SHALLOW TRUE
      GIT_SUBMODULES_RECURSE TRUE)
    FetchContent_MakeAvailable(libdatachannel)
    # Its headers trip -Wpedantic (an extra `;`), and they are not ours.
    foreach(target datachannel datachannel-static)
      if(TARGET ${target})
        set_property(TARGET ${target} APPEND PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
          $<TARGET_PROPERTY:${target},INTERFACE_INCLUDE_DIRECTORIES>)
      endif()
    endforeach()
  endif()
  target_sources(gamend PRIVATE src/libdatachannel_transport.cpp)
  # libdatachannel reports errors by throwing; this one file catches them.
  if(MSVC)
    set_source_files_properties(src/libdatachannel_transport.cpp PROPERTIES COMPILE_OPTIONS "/EHsc")
  else()
    set_source_files_properties(src/libdatachannel_transport.cpp PROPERTIES COMPILE_OPTIONS "-fexceptions")
  endif()
  # Statically when it was fetched, unless the SDK installs: libdatachannel
  # installs only LibDataChannel (shared or static, as BUILD_SHARED_LIBS
  # says), not LibDataChannelStatic.
  if(TARGET LibDataChannel::LibDataChannelStatic AND NOT GAMEND_INSTALL)
    target_link_libraries(gamend PRIVATE LibDataChannel::LibDataChannelStatic)
  else()
    target_link_libraries(gamend PRIVATE LibDataChannel::LibDataChannel)
  endif()
  target_compile_definitions(gamend PUBLIC GAMEND_WITH_WEBRTC=1)
endif()

if(GAMEND_INSTALL)
  include(CMakePackageConfigHelpers)
  set(gamend_cmake_dir ${CMAKE_INSTALL_LIBDIR}/cmake/gamend)
  # For gamendConfig.cmake: where libdatachannel's OpenSSL was, if it used one.
  set(gamend_openssl_root "")
  if(GAMEND_WITH_WEBRTC AND OPENSSL_INCLUDE_DIR)
    get_filename_component(gamend_openssl_root "${OPENSSL_INCLUDE_DIR}" DIRECTORY)
  endif()
  install(TARGETS gamend EXPORT gamendTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
  install(DIRECTORY include/gamend DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
  install(EXPORT gamendTargets NAMESPACE gamend:: DESTINATION ${gamend_cmake_dir})
  configure_package_config_file(cmake/gamendConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/gamendConfig.cmake
    INSTALL_DESTINATION ${gamend_cmake_dir})
  write_basic_package_version_file(${CMAKE_CURRENT_BINARY_DIR}/gamendConfigVersion.cmake
    COMPATIBILITY SameMajorVersion)
  install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/gamendConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/gamendConfigVersion.cmake
    DESTINATION ${gamend_cmake_dir})
endif()

if(GAMEND_BUILD_TESTS)
  enable_testing()
  find_package(doctest CONFIG QUIET)
  if(NOT doctest_FOUND)
    FetchContent_Declare(doctest
      URL https://github.com/doctest/doctest/archive/refs/tags/v2.5.3.tar.gz
      URL_HASH SHA256=174ebc4e769928959614789c5b4e9c3d0a0f81a62bb608756b127bfebfb21331)
    set(DOCTEST_NO_INSTALL ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(doctest)
    set_property(TARGET doctest APPEND PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
      $<TARGET_PROPERTY:doctest,INTERFACE_INCLUDE_DIRECTORIES>)
  endif()
  add_executable(gamend_tests
    tests/main.cpp
    tests/api_test.cpp
    tests/auth_test.cpp
    tests/events_test.cpp
    tests/helpers_test.cpp
    tests/models_test.cpp
    tests/proto_test.cpp
    tests/query_test.cpp
    tests/realtime_test.cpp
    tests/rest_test.cpp
    tests/webrtc_test.cpp)
  target_include_directories(gamend_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_link_libraries(gamend_tests PRIVATE gamend doctest::doctest)
  # The tests hold the headers to the core's rules too: no exceptions, no RTTI.
  # doctest's own forward declaration of std::basic_ostream breaks on MSVC's
  # newer standard library; the real headers do not.
  target_compile_definitions(gamend_tests PRIVATE
    DOCTEST_CONFIG_NO_EXCEPTIONS_BUT_WITH_ALL_ASSERTS DOCTEST_CONFIG_USE_STD_HEADERS)
  gamend_strict(gamend_tests)
  add_test(NAME gamend_tests COMMAND gamend_tests)
endif()

if(GAMEND_BUILD_EXAMPLES AND GAMEND_WITH_CURL)
  add_executable(gamend_conformance examples/conformance.cpp)
  target_link_libraries(gamend_conformance PRIVATE gamend)
  gamend_strict(gamend_conformance)
  if(MSVC)
    # It reads its admin credentials with std::getenv.
    target_compile_definitions(gamend_conformance PRIVATE _CRT_SECURE_NO_WARNINGS)
  endif()
endif()
