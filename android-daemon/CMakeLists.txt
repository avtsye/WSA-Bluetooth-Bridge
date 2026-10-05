cmake_minimum_required(VERSION 3.22.1)
project(wsa_bt_bridge_daemon LANGUAGES CXX)

add_executable(wsa-btd main.cpp)
target_compile_features(wsa-btd PRIVATE cxx_std_20)
target_compile_options(wsa-btd PRIVATE -Wall -Wextra -Wpedantic)
