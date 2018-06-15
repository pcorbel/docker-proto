# docker-proto

# How to use

Where ${proto} is your file.proto

```
docker run \
-v $(pwd):$(pwd) \
-w $(pwd) pierrecorbel/docker-proto:1.0.1 \
/usr/bin/protoc \
-I/protobuf \
--proto_path=src/main/proto \
--java_out=src/main/java \
--python_out=src/main/python \
--swift_out=src/main/swift \
--doc_out=src/main/json \
--doc_opt=json,${proto%%.proto}.json \
${proto}
```
