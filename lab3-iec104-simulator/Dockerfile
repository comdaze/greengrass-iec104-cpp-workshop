# Multi-stage build for IEC104 Simulator
FROM public.ecr.aws/ubuntu/ubuntu:22.04 AS builder

# Install build dependencies and lib60870
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Build and install lib60870
RUN cd /tmp && \
    git clone https://github.com/mz-automation/lib60870.git && \
    cd lib60870/lib60870-C && \
    mkdir build && cd build && \
    cmake .. && make && make install && \
    rm -rf /tmp/lib60870

# Copy nlohmann/json headers
COPY nlohmann/ /usr/local/include/nlohmann/

# Copy source code
WORKDIR /build
COPY src/ ./src/
COPY CMakeLists.txt ./
COPY config.json ./

# Build the simulator
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc)

# Runtime stage
FROM public.ecr.aws/ubuntu/ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Copy lib60870 library from builder
COPY --from=builder /usr/local/lib/liblib60870.so* /usr/local/lib/
RUN ldconfig

# Create non-root user
RUN useradd -m -u 1000 simulator

# Copy binary and config from builder
WORKDIR /app
COPY --from=builder /build/build/iec104_simulator /app/
COPY --from=builder /build/config.json /app/

# Set ownership
RUN chown -R simulator:simulator /app

# Switch to non-root user
USER simulator

# Expose IEC104 port
EXPOSE 2404

# Run simulator
CMD ["/app/iec104_simulator", "/app/config.json"]
