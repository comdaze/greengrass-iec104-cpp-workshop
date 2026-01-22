cmake_minimum_required(VERSION 3.10)
project(hello_world VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(nlohmann_json QUIET)
if(NOT nlohmann_json_FOUND)
    include(FetchContent)
    FetchContent_Declare(
        nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG v3.11.2
    )
    FetchContent_MakeAvailable(nlohmann_json)
endif()

add_executable(hello_world src/hello_world.cpp)
target_link_libraries(hello_world nlohmann_json::nlohmann_json pthread)

install(TARGETS hello_world DESTINATION bin)
