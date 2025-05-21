# Use a lightweight base image with bash and curl
FROM ubuntu:22.04

# Install required packages
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the entire repo into the container
COPY . .

# Make sure the upload script is executable
RUN chmod +x ACEMID_uploader.sh

# Set environment variables (can be overridden at runtime)
ENV XNAT_URL="your_xnat_url"
ENV USERNAME="your_xnat_username"
ENV PASSWORD="your_xnat_password"
ENV PROJECT_ID="your_project_id"

# Default command to run the upload script
CMD ["./ACEMID_uploader.sh"]
