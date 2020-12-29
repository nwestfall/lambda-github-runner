echo "Building Runner Base"
docker build --pull --rm -f "../src/lambda-github-runner/Dockerfile.base" -t lambda-github-runner-base:latest "../src/lambda-github-runner"
echo "Runner Base Built"
echo "Building Runner"
docker build --rm -f "../src/lambda-github-runner/Dockerfile" -t public.ecr.aws/n9q0k4a8/lambda-github-runner:latest "../src/lambda-github-runner"
echo "Runner Built"
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/n9q0k4a8
echo "Pushing Runner Container"
docker push public.ecr.aws/n9q0k4a8/lambda-github-runner:latest
echo "Runner Container Pushed"