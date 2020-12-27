FROM public.ecr.aws/lambda/provided:al2 as build
# install compiler
RUN yum install -y golang
RUN go env -w GOPROXY=direct
# cache dependencies
ADD go.mod go.sum ./
RUN go mod download
# build
ADD main.go .
RUN go build -o /main

FROM lambda-github-runner-base:latest

# Copy Lambda Entrypoint
COPY --from=build /main /main

ENTRYPOINT ["/main"]