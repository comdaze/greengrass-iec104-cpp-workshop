cmake_minimum_required(VERSION 3.10)
project(iot_publisher VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find AWS IoT Device SDK
find_package(aws-crt-cpp REQUIRED)
find_package(GreengrassIpc-cpp REQUIRED)
find_package(IotDeviceCommon-cpp REQUIRED)
find_package(IotDeviceDefender-cpp REQUIRED)

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

add_executable(iot_publisher src/iot_publisher.cpp)

target_link_libraries(iot_publisher 
    nlohmann_json::nlohmann_json 
    AWS::GreengrassIpc-cpp
    AWS::IotDeviceCommon-cpp
    pthread
)

install(TARGETS iot_publisher DESTINATION bin)
