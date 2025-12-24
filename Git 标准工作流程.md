### **Git 标准工作流程（个人开发者 / 团队开发通用）**

------

##### 🚀 1. 克隆项目（只做一次）

##### 🧱 2. 创建个人开发分支（从 main 拉）

> 👉 所有开发在个人分支（如 jxb）进行
> 👉 不要直接在 main 上改代码！

##### 📝 3. 开发 → 添加文件 → 提交本地

> 👉 此时改动仅在本地 jxb，不影响远程。
>

##### 📤 4. 推送到远程个人分支

##### 🔀 5. 合并到 main（通过远程仓库）

> ❌ 不要本地合并到 main 再推送（容易污染 main）
>
> ✔ 远程个人分支合并到远程 main 分支
>
> 👉 在 GitLab 上使用：Merge Request，通过后远程平台自动合并到 main。

##### 🔄 6. 保持本地个人分支与 main 同步

> 👉 合并完成后，本地分支可能落后，因此需要同步 main：
>
> 👉 将最新 main 合并回个人分支：
>
> ```
> git checkout jxb
> git merge main
> ```
>
> 👉 或使用 rebase：
>
> ```
> git checkout jxb
> git rebase main
> ```
>
> 👉 解决冲突后继续开发即可。

------

##### 🔁 7. 循环开发

> 👉 每次进入新需求：
>
> ```
> git checkout main
> git pull
> git checkout -b 新功能分支
> ```
>
> 👉 保持 main 干净、稳定。

------

🎯 **总结：标准 Git 流程图**

```
[main] ← 拉最新代码
   ↓
创建个人分支 jxb
   ↓
写代码
   ↓
git add + commit
   ↓
git push 到远程 jxb
   ↓
发起 Pull Request / Merge Request
   ↓
远程平台合并 jxb → main
   ↓
本地同步 main
   ↓
个人分支合并 main 继续开发
```

**重点**：

> - 每次推送前先拉取。
> - 每次修改后必须 commit（提交），并 push（推送）才能让 GitLab/GitHub 看到改动。
> - 创建合并请求前，确保“分支有差异”。