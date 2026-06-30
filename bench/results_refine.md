# 加入 27B 润色后的对比

ASR 原始输出 → 经自建 Qwen3.6-27B 端点润色（提示词同 app）。CER 已做数字中性化，只衡量术语/文本对错。

## 汇总

| 模型 | 原始 CER | 原始完全正确 | 润色后 CER | 润色后完全正确 |
|---|---|---|---|---|
| 0.6B-4bit | 5.74% | 30/50 | 3.79% | 34/50 |
| 0.6B-8bit | 3.61% | 36/50 | 2.11% | 39/50 |
| 1.7B-4bit | 2.34% | 39/50 | 2.04% | 41/50 |

## 逐句：原始 → 润色

| # | 参考 | 模型 | 原始 ASR | 润色后 | 原CER | 润CER |
|---|---|---|---|---|---|---|
| 0 | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 0.6B-4bit | 我用Python写了一个爬虫，把数据存到MySQL里。 | 我用Python写了一个爬虫，把数据存到MySQL里。 | 0% | 0% |
| 0 | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 0.6B-8bit | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 0% | 0% |
| 0 | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 1.7B-4bit | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 我用 Python 写了一个爬虫，把数据存到 MySQL 里。 | 0% | 0% |
| 1 | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 0.6B-4bit | 这个API返回的是JSON格式，记得做好异常处理。 | 这个API返回的是JSON格式，记得做好异常处理。 | 0% | 0% |
| 1 | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 0.6B-8bit | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 0% | 0% |
| 1 | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 1.7B-4bit | 这个A P I返回的是JSON格式，记得做好异常处理。 | 这个 API 返回的是 JSON 格式，记得做好异常处理。 | 0% | 0% |
| 2 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 0.6B-4bit | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 0% | 0% |
| 2 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 0.6B-8bit | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 0% | 0% |
| 2 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 1.7B-4bit | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 我们用 Docker 把服务打包，然后部署到 Kubernetes 集群上。 | 0% | 0% |
| 3 | 前端用 React，后端用 Node.js，数据库选了 PostgreSQL。 | 0.6B-4bit | 前端用React，后端用Node.js，数据库选了PostgreSQL。 | 前端用React，后端用Node.js，数据库选了PostgreSQL。 | 0% | 0% |
| 3 | 前端用 React，后端用 Node.js，数据库选了 PostgreSQL。 | 0.6B-8bit | 前端用 React，后端用 Node.js。数据库选了 PostgreSQL。 | 前端用 React，后端用 Node.js。数据库选了 PostgreSQL。 | 0% | 0% |
| 3 | 前端用 React，后端用 Node.js，数据库选了 PostgreSQL。 | 1.7B-4bit | 前端用 React，后端用 Node.js，数据库选了 PostgreSQL。 | 前端用 React，后端用 Node.js，数据库选了 PostgreSQL。 | 0% | 0% |
| 4 | 你把这个 bug 修一下，然后提个 pull request 给我 review。 | 0.6B-4bit | 你把这个 book 修一下，然后提个 pull request 给我 review。 | 你把这个 book 修一下，然后提个 pull request 给我 review。 | 9% | 9% |
| 4 | 你把这个 bug 修一下，然后提个 pull request 给我 review。 | 0.6B-8bit | 你把这个 book 修一下，然后提个 pull request 给我 review。 | 你把这个 book 修一下，然后提个 pull request 给我 review。 | 9% | 9% |
| 4 | 你把这个 bug 修一下，然后提个 pull request 给我 review。 | 1.7B-4bit | 你把这个 bug 修一下，然后提个 pull request 给我 review。 | 你把这个 bug 修一下，然后提个 pull request 给我 review。 | 0% | 0% |
| 5 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 0.6B-4bit | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 0% | 0% |
| 5 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 0.6B-8bit | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 0% | 0% |
| 5 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 1.7B-4bit | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 这段代码的时间复杂度太高了，建议改用哈希表优化。 | 0% | 0% |
| 6 | 服务器的 CPU 占用率飙到百分之九十，可能有内存泄漏。 | 0.6B-4bit | 服务器的CPU占用率飙到百分之九十，可能有内存泄漏。 | 服务器的CPU占用率飙到90%，可能有内存泄漏。 | 0% | 0% |
| 6 | 服务器的 CPU 占用率飙到百分之九十，可能有内存泄漏。 | 0.6B-8bit | 服务器的 CPU 占用率飙到百分之九十，可能有内存泄漏。 | 服务器的 CPU 占用率飙到90%，可能有内存泄漏。 | 0% | 0% |
| 6 | 服务器的 CPU 占用率飙到百分之九十，可能有内存泄漏。 | 1.7B-4bit | 服务器的 C P U 占用率飙到百分之九十，可能有内存泄漏。 | 服务器的 CPU 占用率飙到90%，可能有内存泄漏。 | 0% | 0% |
| 7 | 我们的 model 在测试集上的 accuracy 达到了百分之九十五。 | 0.6B-4bit | 我们的模型在测试集上的accuracy达到了百分之九十五。 | 我们的模型在测试集上的accuracy达到了95%。 | 20% | 20% |
| 7 | 我们的 model 在测试集上的 accuracy 达到了百分之九十五。 | 0.6B-8bit | 我们的模型在测试集上的 accuracy 达到了百分之九十五。 | 我们的模型在测试集上的 accuracy 达到了95%。 | 20% | 20% |
| 7 | 我们的 model 在测试集上的 accuracy 达到了百分之九十五。 | 1.7B-4bit | 我们的 model 在测试集上的 accuracy 达到了百分之九十五。 | 我们的 model 在测试集上的 accuracy 达到了95%。 | 0% | 0% |
| 8 | 用 Redis 做缓存可以显著降低数据库的 latency。 | 0.6B-4bit | 用 Redis 做缓存，可以显著降低数据库的 latency。 | 用 Redis 做缓存，可以显著降低数据库的 latency。 | 0% | 0% |
| 8 | 用 Redis 做缓存可以显著降低数据库的 latency。 | 0.6B-8bit | 用 Redis 做缓存可以显著降低数据库的 latency。 | 用 Redis 做缓存可以显著降低数据库的 latency。 | 0% | 0% |
| 8 | 用 Redis 做缓存可以显著降低数据库的 latency。 | 1.7B-4bit | 用 Redis 做缓存，可以显著降低数据库的 latency。 | 用 Redis 做缓存，可以显著降低数据库的 latency。 | 0% | 0% |
| 9 | 这个 function 有 side effect，最好改成纯函数。 | 0.6B-4bit | 这个 function 有 side effect，最好改成纯函数。 | 这个 function 有 side effect，最好改成纯函数。 | 0% | 0% |
| 9 | 这个 function 有 side effect，最好改成纯函数。 | 0.6B-8bit | 这个 function 有 side effect，最好改成纯函数。 | 这个 function 有 side effect，最好改成纯函数。 | 0% | 0% |
| 9 | 这个 function 有 side effect，最好改成纯函数。 | 1.7B-4bit | 这个 function 有 side effect，最好改成纯函数。 | 这个 function 有 side effect，最好改成纯函数。 | 0% | 0% |
| 10 | 我把 feature branch merge 到 main 之前先跑一遍 CI。 | 0.6B-4bit | 我把feature branch merge到main之前，先跑一遍词。 | 我把 feature branch merge 到 main 之前，先跑一遍测试。 | 6% | 6% |
| 10 | 我把 feature branch merge 到 main 之前先跑一遍 CI。 | 0.6B-8bit | 我把 feature branch merge 到 main 之前，先跑一遍磁。 | 我把 feature branch merge 到 main 之前，先跑一遍测试。 | 6% | 6% |
| 10 | 我把 feature branch merge 到 main 之前先跑一遍 CI。 | 1.7B-4bit | 我把 feature branch merge 到 main 之前，先跑一遍词。 | 我把 feature branch merge 到 main 之前，先跑一遍测试。 | 6% | 6% |
| 11 | Transformer 的 attention 机制是这篇论文的核心创新。 | 0.6B-4bit | Transformer的Attention机制是这篇论文的核心创新。 | Transformer的Attention机制是这篇论文的核心创新。 | 0% | 0% |
| 11 | Transformer 的 attention 机制是这篇论文的核心创新。 | 0.6B-8bit | Transformer的Attention机制是这篇论文的核心创新。 | Transformer的Attention机制是这篇论文的核心创新。 | 0% | 0% |
| 11 | Transformer 的 attention 机制是这篇论文的核心创新。 | 1.7B-4bit | Transformer的Attention机制是这篇论文的核心创新。 | Transformer的Attention机制是这篇论文的核心创新。 | 0% | 0% |
| 12 | 你检查一下 nginx 的配置，反向代理好像没生效。 | 0.6B-4bit | 你检查一下Nginx的配置，反向代理好像没生效。 | 你检查一下Nginx的配置，反向代理好像没生效。 | 0% | 0% |
| 12 | 你检查一下 nginx 的配置，反向代理好像没生效。 | 0.6B-8bit | 你检查一下 Nginx 的配置，反向代理好像没生效。 | 你检查一下 Nginx 的配置，反向代理好像没生效。 | 0% | 0% |
| 12 | 你检查一下 nginx 的配置，反向代理好像没生效。 | 1.7B-4bit | 你检查一下 Nginx 的配置，反向代理好像没生效。 | 你检查一下 Nginx 的配置，反向代理好像没生效。 | 0% | 0% |
| 13 | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 0.6B-4bit | 这个项目用了Micro Services架构，服务之间通过GRPC通信。 | 这个项目用了 Micro Services 架构，服务之间通过 gRPC 通信。 | 0% | 0% |
| 13 | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 0.6B-8bit | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 0% | 0% |
| 13 | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 1.7B-4bit | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 这个项目用了 microservices 架构，服务之间通过 gRPC 通信。 | 0% | 0% |
| 14 | 把 log level 调成 debug，方便我们定位问题。 | 0.6B-4bit | 把 log level 调成 debug，方便我们定位问题。 | 把 log level 调成 debug，方便我们定位问题。 | 0% | 0% |
| 14 | 把 log level 调成 debug，方便我们定位问题。 | 0.6B-8bit | 把 log level 调成 debug，方便我们定位问题。 | 把 log level 调成 debug，方便我们定位问题。 | 0% | 0% |
| 14 | 把 log level 调成 debug，方便我们定位问题。 | 1.7B-4bit | 把 log level 调成 debug，方便我们定位问题。 | 把 log level 调成 debug，方便我们定位问题。 | 0% | 0% |
| 15 | 我们需要做一次 code review，顺便重构一下这个 module。 | 0.6B-4bit | 我们需要做一次 code review，顺便重构一下这个 module。 | 我们需要做一次 code review，顺便重构一下这个 module。 | 0% | 0% |
| 15 | 我们需要做一次 code review，顺便重构一下这个 module。 | 0.6B-8bit | 我们需要做一次 code review，顺便重构一下这个 module。 | 我们需要做一次 code review，顺便重构一下这个 module。 | 0% | 0% |
| 15 | 我们需要做一次 code review，顺便重构一下这个 module。 | 1.7B-4bit | 我们需要做一次 code review，顺便重构一下这个 module。 | 我们需要做一次 code review，顺便重构一下这个 module。 | 0% | 0% |
| 16 | GPU 显存不够了，把 batch size 调小一点试试。 | 0.6B-4bit | GPU显存不够了，把batch size调小一点试试。 | GPU显存不够了，把batch size调小一点试试。 | 0% | 0% |
| 16 | GPU 显存不够了，把 batch size 调小一点试试。 | 0.6B-8bit | GPU显存不够了，把batch size调小一点试试。 | GPU显存不够了，把batch size调小一点试试。 | 0% | 0% |
| 16 | GPU 显存不够了，把 batch size 调小一点试试。 | 1.7B-4bit | G P U显存不够了，把 batch size 调小一点试试。 | GPU显存不够了，把 batch size 调小一点试试。 | 0% | 0% |
| 17 | 这个 SQL 查询没走索引，所以特别慢。 | 0.6B-4bit | 这个SQL查询没走索引，所以特别慢。 | 这个SQL查询没走索引，所以特别慢。 | 0% | 0% |
| 17 | 这个 SQL 查询没走索引，所以特别慢。 | 0.6B-8bit | 这个 SQL 查询没走索引，所以特别慢。 | 这个 SQL 查询没走索引，所以特别慢。 | 0% | 0% |
| 17 | 这个 SQL 查询没走索引，所以特别慢。 | 1.7B-4bit | 这个 S Q L 查询没走索引，所以特别慢。 | 这个 SQL 查询没走索引，所以特别慢。 | 0% | 0% |
| 18 | 用 TypeScript 能在编译期就发现很多类型错误。 | 0.6B-4bit | 用 TypeScript，能在编译期就发现很多类型错误。 | 用 TypeScript，能在编译期就发现很多类型错误。 | 0% | 0% |
| 18 | 用 TypeScript 能在编译期就发现很多类型错误。 | 0.6B-8bit | 用 TypeScript 能在编译期就发现很多类型错误。 | 用 TypeScript 能在编译期就发现很多类型错误。 | 0% | 0% |
| 18 | 用 TypeScript 能在编译期就发现很多类型错误。 | 1.7B-4bit | 用 TypeScript 能在编译期就发现很多类型错误。 | 用 TypeScript 能在编译期就发现很多类型错误。 | 0% | 0% |
| 19 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 0.6B-4bit | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 0% | 0% |
| 19 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 0.6B-8bit | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 0% | 0% |
| 19 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 1.7B-4bit | 我们的 C D N 节点覆盖全球，静态资源加载很快。 | 我们的 CDN 节点覆盖全球，静态资源加载很快。 | 0% | 0% |
| 20 | 这个 endpoint 需要鉴权，记得在 header 里带上 token。 | 0.6B-4bit | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 6% | 6% |
| 20 | 这个 endpoint 需要鉴权，记得在 header 里带上 token。 | 0.6B-8bit | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 6% | 6% |
| 20 | 这个 endpoint 需要鉴权，记得在 header 里带上 token。 | 1.7B-4bit | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 这个 endpoint 需要健全，记得在 header 里带上 token。 | 6% | 6% |
| 21 | 机器学习里 overfitting 是个常见问题，可以用 dropout 缓解。 | 0.6B-4bit | 机器学习里Overfitting是个常见问题，可以用Dropout缓解。 | 机器学习里Overfitting是个常见问题，可以用Dropout缓解。 | 0% | 0% |
| 21 | 机器学习里 overfitting 是个常见问题，可以用 dropout 缓解。 | 0.6B-8bit | 机器学习里 overfitting 是个常见问题，可以用 dropout 环节。 | 机器学习里 overfitting 是个常见问题，可以用 dropout 缓解。 | 6% | 0% |
| 21 | 机器学习里 overfitting 是个常见问题，可以用 dropout 缓解。 | 1.7B-4bit | 机器学习里，overfitting是个常见问题，可以用dropout缓解。 | 机器学习里，overfitting是个常见问题，可以用dropout缓解。 | 0% | 0% |
| 22 | 把这个组件抽成一个可复用的 hook，逻辑会清晰很多。 | 0.6B-4bit | 把这个组件抽成一个可复用的逻辑，会清晰很多。 | 把这个组件抽成一个可复用的逻辑，会清晰很多。 | 17% | 17% |
| 22 | 把这个组件抽成一个可复用的 hook，逻辑会清晰很多。 | 0.6B-8bit | 把这个组件抽成一个可复用的 Hook，逻辑会清晰很多。 | 把这个组件抽成一个可复用的 Hook，逻辑会清晰很多。 | 0% | 0% |
| 22 | 把这个组件抽成一个可复用的 hook，逻辑会清晰很多。 | 1.7B-4bit | 把这个组件抽成一个可复用的 hook，逻辑会清晰很多。 | 把这个组件抽成一个可复用的 hook，逻辑会清晰很多。 | 0% | 0% |
| 23 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 0.6B-4bit | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 0% | 0% |
| 23 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 0.6B-8bit | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 0% | 0% |
| 23 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 1.7B-4bit | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 我们用 Kafka 做消息队列，处理高并发的事件流。 | 0% | 0% |
| 24 | 这个算法用了动态规划，把子问题的结果 cache 起来。 | 0.6B-4bit | 这个算法用了动态规划，把子问题的结果推想起来。 | 这个算法用了动态规划，把子问题的结果 cache 起来。 | 21% | 0% |
| 24 | 这个算法用了动态规划，把子问题的结果 cache 起来。 | 0.6B-8bit | 这个算法用了动态规划，把子问题的结果初始化来。 | 这个算法用了动态规划，把子问题的结果 cache 起来。 | 25% | 0% |
| 24 | 这个算法用了动态规划，把子问题的结果 cache 起来。 | 1.7B-4bit | 这个算法用了动态规划，把子问题的结果cache起来。 | 这个算法用了动态规划，把子问题的结果cache起来。 | 0% | 0% |
| 25 | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 0.6B-4bit | 部署的时候，记得设置好环境变量，别把secret写死在代码里。 | 部署的时候，记得设置好环境变量，别把 secret 写死在代码里。 | 0% | 0% |
| 25 | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 0.6B-8bit | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 0% | 0% |
| 25 | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 1.7B-4bit | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 部署的时候记得设置好环境变量，别把 secret 写死在代码里。 | 0% | 0% |
| 26 | 这次性能优化主要是减少了不必要的 re-render。 | 0.6B-4bit | 这次性能优化主要是减少了不必要的热 render。 | 这次性能优化主要是减少了不必要的热 render。 | 8% | 8% |
| 26 | 这次性能优化主要是减少了不必要的 re-render。 | 0.6B-8bit | 这次性能优化主要是减少了不必要的热 render。 | 这次性能优化主要是减少了不必要的热 render。 | 8% | 8% |
| 26 | 这次性能优化主要是减少了不必要的 re-render。 | 1.7B-4bit | 这次性能优化主要是减少了不必要的热 render。 | 这次性能优化主要是减少了不必要的热 render。 | 8% | 8% |
| 27 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 0.6B-4bit | 我们的数据 pipeline 是用 Airflow 来调度的。 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 0% | 0% |
| 27 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 0.6B-8bit | 我们的数据 pipeline 是用 Airflow 来调度的。 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 0% | 0% |
| 27 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 1.7B-4bit | 我们的数据 pipeline 是用 Airflow 来调度的。 | 我们的数据 pipeline 是用 Airflow 来调度的。 | 0% | 0% |
| 28 | 这个接口有 race condition，需要加个锁来保证线程安全。 | 0.6B-4bit | 这个接口有 risk condition，需要加个锁来保证进程安全。 | 这个接口有 risk condition，需要加个锁来保证进程安全。 | 13% | 13% |
| 28 | 这个接口有 race condition，需要加个锁来保证线程安全。 | 0.6B-8bit | 这个接口有 risk condition，需要加个锁来保证线程安全。 | 这个接口有 risk condition，需要加个锁来保证线程安全。 | 10% | 10% |
| 28 | 这个接口有 race condition，需要加个锁来保证线程安全。 | 1.7B-4bit | 这个接口有 risk condition，需要加个锁来保证线程安全。 | 这个接口有 risk condition，需要加个锁来保证线程安全。 | 10% | 10% |
| 29 | 用 webpack 打包之后，记得开启 tree shaking 减小体积。 | 0.6B-4bit | 用Web Pack打包之后，记得开启Tree Shaking，减小体积。 | 用 Webpack 打包之后，记得开启 Tree Shaking，减小体积。 | 0% | 0% |
| 29 | 用 webpack 打包之后，记得开启 tree shaking 减小体积。 | 0.6B-8bit | 用 Webpack 打包之后，记得开启 Tree Shaking，减小体积。 | 用 Webpack 打包之后，记得开启 Tree Shaking，减小体积。 | 0% | 0% |
| 29 | 用 webpack 打包之后，记得开启 tree shaking 减小体积。 | 1.7B-4bit | 用 webpack 打包之后，记得开启 tree shaking，减小体积。 | 用 webpack 打包之后，记得开启 tree shaking，减小体积。 | 0% | 0% |
| 30 | 这个 PR 里有个 typo，变量名拼错了。 | 0.6B-4bit | 这个T R里有个typeo变量名拼错了。 | 这个 TR 里有个 typo 变量名拼错了。 | 12% | 6% |
| 30 | 这个 PR 里有个 typo，变量名拼错了。 | 0.6B-8bit | 这个tr里有个typeo，变量名拼错了。 | 这个 PR 里有个 typo，变量名拼错了。 | 12% | 0% |
| 30 | 这个 PR 里有个 typo，变量名拼错了。 | 1.7B-4bit | 这个 per 里有个 type 变量名拼错了。 | 这个 per 里有个 type 变量名拼错了。 | 12% | 12% |
| 31 | 我们把单体应用拆成了几个独立的 service。 | 0.6B-4bit | 我们把单体应用拆成了几个独立的service。 | 我们把单体应用拆成了几个独立的 service。 | 0% | 0% |
| 31 | 我们把单体应用拆成了几个独立的 service。 | 0.6B-8bit | 我们把单体应用拆成了几个独立的 service。 | 我们把单体应用拆成了几个独立的 service。 | 0% | 0% |
| 31 | 我们把单体应用拆成了几个独立的 service。 | 1.7B-4bit | 我们把单体应用拆成了几个独立的 service。 | 我们把单体应用拆成了几个独立的 service。 | 0% | 0% |
| 32 | 这个 query 应该用 join 而不是写好几个子查询。 | 0.6B-4bit | 这个查询应该用 join 而不是写好几个子查询。 | 这个查询应该用 join 而不是写好几个子查询。 | 21% | 21% |
| 32 | 这个 query 应该用 join 而不是写好几个子查询。 | 0.6B-8bit | 这个 query 应该用 join 而不是写好几个子查询。 | 这个 query 应该用 join 而不是写好几个子查询。 | 0% | 0% |
| 32 | 这个 query 应该用 join 而不是写好几个子查询。 | 1.7B-4bit | 这个 query 应该用 join 而不是写好几个字查询。 | 这个 query 应该用 join 而不是写好几个子查询。 | 4% | 0% |
| 33 | 训练的时候 loss 一直不收敛，可能是 learning rate 太大了。 | 0.6B-4bit | 训练的时候，Luc一直不收敛，可能是Learning Rate太大了。 | 训练的时候，Loss一直不收敛，可能是Learning Rate太大了。 | 10% | 0% |
| 33 | 训练的时候 loss 一直不收敛，可能是 learning rate 太大了。 | 0.6B-8bit | 训练的时候loss一直不收敛，可能是learning rate太大了。 | 训练的时候loss一直不收敛，可能是learning rate太大了。 | 0% | 0% |
| 33 | 训练的时候 loss 一直不收敛，可能是 learning rate 太大了。 | 1.7B-4bit | 训练的时候 loss 一直不收敛，可能是 learning rate 太大了。 | 训练的时候 loss 一直不收敛，可能是 learning rate 太大了。 | 0% | 0% |
| 34 | 把 HTTPS 证书配好，不然浏览器会报警告。 | 0.6B-4bit | 把 HTTP 证书配好，不然浏览器会报警告。 | 把 HTTP 证书配好，不然浏览器会报警告。 | 5% | 5% |
| 34 | 把 HTTPS 证书配好，不然浏览器会报警告。 | 0.6B-8bit | 把 HTTPS 证书配好，不然浏览器会报警告。 | 把 HTTPS 证书配好，不然浏览器会报警告。 | 0% | 0% |
| 34 | 把 HTTPS 证书配好，不然浏览器会报警告。 | 1.7B-4bit | 把 HTTPS 证书配好，不然浏览器会报警告。 | 把 HTTPS 证书配好，不然浏览器会报警告。 | 0% | 0% |
| 35 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 0.6B-4bit | 这个library有个已知的 vulnerability，赶紧升级版本。 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 0% | 0% |
| 35 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 0.6B-8bit | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 0% | 0% |
| 35 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 1.7B-4bit | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 这个 library 有个已知的 vulnerability，赶紧升级版本。 | 0% | 0% |
| 36 | 我们用 Prometheus 加 Grafana 来做监控和告警。 | 0.6B-4bit | 我們用 Prometheus 加 Grafana 来做監控和告警。 | 我們用 Prometheus 加 Grafana 来做監控和告警。 | 7% | 7% |
| 36 | 我们用 Prometheus 加 Grafana 来做监控和告警。 | 0.6B-8bit | 我们用 Prometheus 加 Grafana 来做监控和报警。 | 我们用 Prometheus 加 Grafana 来做监控和报警。 | 4% | 4% |
| 36 | 我们用 Prometheus 加 Grafana 来做监控和告警。 | 1.7B-4bit | 我们用 Promises 加 Grafana 来做监控和告警。 | 我们用 Promises 加 Grafana 来做监控和告警。 | 14% | 14% |
| 37 | 这段逻辑放在 middleware 里处理会更合适。 | 0.6B-4bit | 这段逻辑放在 Mid Lua 里处理会更合适。 | 这段逻辑放在 Mid Lua 里处理会更合适。 | 22% | 22% |
| 37 | 这段逻辑放在 middleware 里处理会更合适。 | 0.6B-8bit | 这段逻辑放在 meetler 里处理会更合适。 | 这段逻辑放在 metler 里处理会更合适。 | 26% | 26% |
| 37 | 这段逻辑放在 middleware 里处理会更合适。 | 1.7B-4bit | 这段逻辑放在 Meteor 里处理会更合适。 | 这段逻辑放在 Meteor 里处理会更合适。 | 30% | 30% |
| 38 | 数据库做了读写分离，read replica 分担了查询压力。 | 0.6B-4bit | 数据库做了读写分离（read replica），分担了查询压力。 | 数据库做了读写分离（read replica），分担了查询压力。 | 0% | 0% |
| 38 | 数据库做了读写分离，read replica 分担了查询压力。 | 0.6B-8bit | 数据库做了读写分离，read replica分担了查询压力。 | 数据库做了读写分离，read replica分担了查询压力。 | 0% | 0% |
| 38 | 数据库做了读写分离，read replica 分担了查询压力。 | 1.7B-4bit | 数据库做了读写分离，Read Replica分担了查询压力。 | 数据库做了读写分离，Read Replica分担了查询压力。 | 0% | 0% |
| 39 | 这个深度学习模型用的是 ResNet 作为 backbone。 | 0.6B-4bit | 这个深度学习模型用的是Vision Net作为 backbone。 | 这个深度学习模型用的是 Vision Net 作为 backbone。 | 19% | 19% |
| 39 | 这个深度学习模型用的是 ResNet 作为 backbone。 | 0.6B-8bit | 这个深度学习模型用的是
ResNet作为 backbone。 | 这个深度学习模型用的是 ResNet 作为 backbone。 | 0% | 0% |
| 39 | 这个深度学习模型用的是 ResNet 作为 backbone。 | 1.7B-4bit | 这个深度学习模型用的是 VGGNet 作为 backbone。 | 这个深度学习模型用的是 VGGNet 作为 backbone。 | 11% | 11% |
| 40 | 你先把 dependency 装好，再运行这个 script。 | 0.6B-4bit | 你先把dependency装好，再运行这个script。 | 你先把 dependency 装好，再运行这个 script。 | 0% | 0% |
| 40 | 你先把 dependency 装好，再运行这个 script。 | 0.6B-8bit | 你先把 dependency 装好，再运行这个 script。 | 你先把 dependency 装好，再运行这个 script。 | 0% | 0% |
| 40 | 你先把 dependency 装好，再运行这个 script。 | 1.7B-4bit | 你先把 dependency 装好，再运行这个 script。 | 你先把 dependency 装好，再运行这个 script。 | 0% | 0% |
| 41 | 我们的 CI/CD 流水线是用 GitHub Actions 搭的。 | 0.6B-4bit | 我们的词 C D 流水線是用 git have action start 的。 | 我们的 CI/CD 流水线是用 GitHub Actions 搭建的。 | 39% | 4% |
| 41 | 我们的 CI/CD 流水线是用 GitHub Actions 搭的。 | 0.6B-8bit | 我们的词 C D 流水线是用 Git have action start 的。 | 我们的 CI/CD 流水线是用 GitHub Actions 搭建的。 | 36% | 4% |
| 41 | 我们的 CI/CD 流水线是用 GitHub Actions 搭的。 | 1.7B-4bit | 我们的词 C D 流水线是用 GitHub Actions 搭的。 | 我们的 CI/CD 流水线是用 GitHub Actions 搭的。 | 11% | 0% |
| 42 | 这个 bug 只在 production 环境复现，本地跑没问题。 | 0.6B-4bit | 这个Bog之在production环境复现本地跑，没问题。 | 这个 Bug 只在 production 环境复现，本地跑没问题。 | 7% | 0% |
| 42 | 这个 bug 只在 production 环境复现，本地跑没问题。 | 0.6B-8bit | 这个 bug 只在 production 环境复现，本地跑没问题。 | 这个 bug 只在 production 环境复现，本地跑没问题。 | 0% | 0% |
| 42 | 这个 bug 只在 production 环境复现，本地跑没问题。 | 1.7B-4bit | 这个 bug 只在 production 环境复现，本地跑没问题。 | 这个 bug 只在 production 环境复现，本地跑没问题。 | 0% | 0% |
| 43 | 用 async await 写异步代码比 callback 清晰太多了。 | 0.6B-4bit | 用 a sinca wait 写一部代码，比 kale back 清晰太多了。 | 用 async await 写一部代码，比 callback 清晰太多了。 | 17% | 7% |
| 43 | 用 async await 写异步代码比 callback 清晰太多了。 | 0.6B-8bit | 用 a sync await 写一部代码，比 callback 清晰太多了。 | 用 async await 写一部代码，比 callback 清晰太多了。 | 7% | 7% |
| 43 | 用 async await 写异步代码比 callback 清晰太多了。 | 1.7B-4bit | 用 async await 写一步代码，比 callback 清晰太多了。 | 用 async await 写一步代码，比 callback 清晰太多了。 | 3% | 3% |
| 44 | 这个表的数据量太大了，得考虑做分库分表。 | 0.6B-4bit | 这个表的数据量太大了，得考虑做分库分表。 | 这个表的数据量太大了，得考虑做分库分表。 | 0% | 0% |
| 44 | 这个表的数据量太大了，得考虑做分库分表。 | 0.6B-8bit | 这个表的数据量太大了，得考虑做分库分表。 | 这个表的数据量太大了，得考虑做分库分表。 | 0% | 0% |
| 44 | 这个表的数据量太大了，得考虑做分库分表。 | 1.7B-4bit | 这个表的数据量太大了，得考虑做分库分表。 | 这个表的数据量太大了，得考虑做分库分表。 | 0% | 0% |
| 45 | 我们用 OAuth 做第三方登录的授权。 | 0.6B-4bit | 我們用 OAuth做第三方登錄的授權。 | 我們用 OAuth 做第三方登錄的授權。 | 19% | 19% |
| 45 | 我们用 OAuth 做第三方登录的授权。 | 0.6B-8bit | 我们用 OAuth 做第三方登录的授权。 | 我们用 OAuth 做第三方登录的授权。 | 0% | 0% |
| 45 | 我们用 OAuth 做第三方登录的授权。 | 1.7B-4bit | 我们用 OAuth 做第三方登录的授权。 | 我们用 OAuth 做第三方登录的授权。 | 0% | 0% |
| 46 | 这个 component 的 state 管理用 Redux 有点重，换成 Zustand 吧。 | 0.6B-4bit | 这个Component of State管理用Redux有点重，换成 Zustant吧。 | 这个 Component 的 State 管理用 Redux 有点重，换成 Zustand 吧。 | 8% | 0% |
| 46 | 这个 component 的 state 管理用 Redux 有点重，换成 Zustand 吧。 | 0.6B-8bit | 这个 component of state 管理用 Redux 有点重，换成 Zustand 吧。 | 这个 component of state 管理用 Redux 有点重，换成 Zustand 吧。 | 5% | 5% |
| 46 | 这个 component 的 state 管理用 Redux 有点重，换成 Zustand 吧。 | 1.7B-4bit | 这个 component 的 state 管理用 Redux 有点重，换成 Zustand 吧。 | 这个 component 的 state 管理用 Redux 有点重，换成 Zustand 吧。 | 0% | 0% |
| 47 | 把缓存策略改成 LRU，命中率会更高。 | 0.6B-4bit | 把缓存策略改成L R U，命中率会更高。 | 把缓存策略改成LRU，命中率会更高。 | 0% | 0% |
| 47 | 把缓存策略改成 LRU，命中率会更高。 | 0.6B-8bit | 把缓存策略改成 LRU，命中率会更高。 | 把缓存策略改成 LRU，命中率会更高。 | 0% | 0% |
| 47 | 把缓存策略改成 LRU，命中率会更高。 | 1.7B-4bit | 把缓存策略改成 LRU，命中率会更高。 | 把缓存策略改成 LRU，命中率会更高。 | 0% | 0% |
| 48 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 0.6B-4bit | 这个模型推理太慢，可以试试量化或者蒸馏。 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 0% | 0% |
| 48 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 0.6B-8bit | 这个模型推理太慢，可以试试量化或者蒸馏。 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 0% | 0% |
| 48 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 1.7B-4bit | 这个模型推理太慢，可以试试量化或者蒸馏。 | 这个模型推理太慢，可以试试量化或者蒸馏。 | 0% | 0% |
| 49 | 我们的 backend 用 Go 重写之后，吞吐量提升了好几倍。 | 0.6B-4bit | 我们的 backend 用 go 重写之后，吞吐量提升了好几倍。 | 我们的 backend 用 go 重写之后，吞吐量提升了好几倍。 | 0% | 0% |
| 49 | 我们的 backend 用 Go 重写之后，吞吐量提升了好几倍。 | 0.6B-8bit | 我们的 backend 用 go 重写之后，吞吐量提升了好几倍。 | 我们的 backend 用 go 重写之后，吞吐量提升了好几倍。 | 0% | 0% |
| 49 | 我们的 backend 用 Go 重写之后，吞吐量提升了好几倍。 | 1.7B-4bit | 我们的 backend 用 Go 重写之后，吞吐量提升了好几倍。 | 我们的 backend 用 Go 重写之后，吞吐量提升了好几倍。 | 0% | 0% |
