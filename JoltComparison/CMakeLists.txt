cmake_minimum_required(VERSION 3.20)

project(JoltComparison LANGUAGES CXX)

# The Jolt tag to fetch and measure. compare.py passes --jolt-version here.
set(JOLT_VERSION v5.6.0 CACHE STRING "Jolt Physics tag to build and compare against")

# Build Jolt the way it ships: its CMake defines a "Distribution" configuration
# (Release without profiler, debug renderer or asserts) and these flags. They
# are set in Jolt's own directory scope, and Jolt's math is header-only, so the
# harness must be compiled with the same flags for the inlined math to match.
# Jolt's instruction-set flags are public on its target, so they reach the
# harness without repeating them here.
if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Distribution)
endif()
# Visual Studio builds pick the configuration at build time, from this list.
set(CMAKE_CONFIGURATION_TYPES "Debug;Release;Distribution")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if (MSVC)
    # MSVC and clang-cl, with Jolt's static runtime: the two must match to link.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    string(REPLACE "/EHsc" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Zc:__cplusplus /Gm- /MP /nologo /diagnostics:classic /FC /fp:except- /Zc:inline /GR- /wd4577")
    if (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /fp:fast")
    else()
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Qunused-arguments")
    endif()
    set(CMAKE_CXX_FLAGS_DISTRIBUTION "/GS- /Gy /O2 /Oi /Ot")
else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-rtti -fno-exceptions -ffp-contract=on")
    if (CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -faligned-allocation")
    endif()
    set(CMAKE_CXX_FLAGS_DISTRIBUTION "-O3")
endif()
set(CMAKE_EXE_LINKER_FLAGS_DISTRIBUTION "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_DISTRIBUTION ON)

set(TARGET_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(TARGET_HELLO_WORLD OFF CACHE BOOL "" FORCE)
set(TARGET_PERFORMANCE_TEST OFF CACHE BOOL "" FORCE)
set(TARGET_SAMPLES OFF CACHE BOOL "" FORCE)
set(TARGET_VIEWER OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
# GPU compute backends are irrelevant to CPU math benchmarks.
set(JPH_USE_DX12 OFF CACHE BOOL "" FORCE)
set(JPH_USE_VK OFF CACHE BOOL "" FORCE)
set(JPH_USE_MTL OFF CACHE BOOL "" FORCE)
# Warnings-as-errors in Jolt only breaks builds on newer compilers; it does not
# change generated code.
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)

include(FetchContent)
FetchContent_Declare(
    JoltPhysics
    GIT_REPOSITORY https://github.com/jrouwe/JoltPhysics.git
    GIT_TAG ${JOLT_VERSION}
    GIT_SHALLOW TRUE
    SOURCE_SUBDIR Build
)
FetchContent_MakeAvailable(JoltPhysics)

add_executable(jolt_primitives Primitives.cpp)
target_link_libraries(jolt_primitives PRIVATE Jolt)
target_compile_definitions(jolt_primitives PRIVATE JOLT_VERSION="${JOLT_VERSION}")
