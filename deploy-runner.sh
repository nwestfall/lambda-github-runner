echo "Building Runner Base"
docker build --pull --rm -f "src/lambda-github-runner/Dockerfile.base" -t lambda-github-runner-base:latest "src/lambda-github-runner"
echo "Runner Base Built"
echo "Building Runner"
docker build --rm -f "src/lambda-github-runner/Dockerfile" -t 034828384224.dkr.ecr.us-east-1.amazonaws.com/lambda-github-runner:latest "src/lambda-github-runner"
echo "Runner Built"
$(aws ecr get-login --region us-east-1 --no-include-email)
echo "Pushing Runner Container"
docker push 034828384224.dkr.ecr.us-east-1.amazonaws.com/lambda-github-runner:latest
echo "Runner Container Pushed"