cmake_minimum_required(VERSION 3.10)
project(iec104_simulator VERSION 1.0.0)

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

include_directories(/usr/local/include/lib60870)

add_executable(iec104_simulator src/simulator.cpp)
target_link_libraries(iec104_simulator 
    nlohmann_json::nlohmann_json
    lib60870
    pthread
)

install(TARGETS iec104_simulator DESTINATION bin)
