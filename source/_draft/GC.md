---
mathjax: true
---

GC(自动垃圾回收)的主要问题:

1. 额外的开销(内存/CPU)
2. 执行GC的时机无法预测，在实时性要求高的场景或事务处理来说可能是不可容忍的
3. 部分GC算法会Stop-the-world


#### 引用计数(Reference counting):

为每个对象维护一个计数，保存其它对象指向它的引用数量。当一个引用被覆盖或销毁，该引用对象的引用计数-1，当一个引用被建立或拷贝，引用对象的引用计数+1，如果对象的引用计数为0，则表明该对象不再被访问(inaccessible)，将被回收。引用计数有如下优缺点:

优点:

1. GC开销将被均摊到程序运行期，不会有长时间的回收周期。
2. 每个对象的生命周期被明确定义。
3. 算法简单，易于实现。
4. 即时回收，不会等内存状态到达某个阀值再执行回收。

缺点:

1. 引用计数会频繁更新，带来效率开销
2. 原生的引用计数算法无法回收循环引用的对象链(A->B->A)

行内的表达式 $$ |a|<1 $$

The **characteristic polynomial** $\chi(\lambda)$ of the $3 \times 3$ matrix
$$
\left( \begin{array}{ccc}
a & b & c \\
d & e & f \\
g & h & i
\end{array} \right)
$$
is given by the formula
$$
\chi(\lambda) = \left| \begin{array}{ccc}
\lambda - a & -b & -c \\
-d & \lambda - e & -f \\
-g & -h & \lambda - i
\end{array} \right|.
$$




$$ x = a_{1}^n + a_{2}^n + a_{3}^n $$
