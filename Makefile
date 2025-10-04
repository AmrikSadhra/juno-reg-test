# Compiler and flags
CXX := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2
LDFLAGS := 

# Target executable
TARGET := reg-test

# Source files
SRCS := reg-test.cpp

# Object files
OBJS := $(SRCS:.cpp=.o)

# Header dependencies
HEADERS := enum.h bitmanip.hpp

# Default target
all: $(TARGET)

# Link the executable
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

# Compile source files
%.o: %.cpp $(HEADERS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Clean build artifacts
clean:
	rm -f $(OBJS) $(TARGET)

# Run all tests with verbose
run-all: $(TARGET)
	sudo ./$(TARGET) -v -l -r

# Install (optional - copy to /usr/local/bin)
install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/

# Uninstall
uninstall:
	rm -f /usr/local/bin/$(TARGET)

# Phony targets
.PHONY: all clean run-all install uninstall

# Help target
help:
	@echo "Available targets:"
	@echo "  all          - Build the executable (default)"
	@echo "  clean        - Remove build artifacts"
	@echo "  run          - Run the program (requires sudo)"
	@echo "  run-verbose  - Run with verbose logging"
	@echo "  run-led      - Run LED test sequence"
	@echo "  run-rng      - Run RNG test sequence"
	@echo "  run-all      - Run all tests with verbose output"
	@echo "  install      - Install to /usr/local/bin"
	@echo "  uninstall    - Remove from /usr/local/bin"
	@echo "  help         - Show this help message"