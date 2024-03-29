---
title: Coursera 《Neural Networks and Deep Learning》 笔记
layout: post
mathjax: true
categiries: AI
tags:
- machine learning
---

本文是Coursera课程[Neural Networks and Deep Learning](https://www.coursera.org/learn/neural-networks-deep-learning)的学习笔记，课程本身深入浅出，质量非常高，这里主要做思路整理和知识备忘，很多模块还需要自己扩展。

什么是深度学习(Deep Learning)？简单来说，深度学习是机器学习的一个子领域，研究受人工神经网络的大脑的结构和功能启发而创造的算法。Wiki上给出的解释则更复杂一点: 深度学习（deep learning）是机器学习的分支，是一种试图使用包含复杂结构或由多重非线性变换构成的多个处理层对数据进行高层抽象的算法。

### 一. 逻辑回归模型

监督学习(Supervised learning): 是一个机器学习中的方法，可以由训练资料中学到或建立一个模式（函数 / learning model），并依此模式推测新的实例。训练资料是由输入物件（通常表示为张量）和预期输出（Label标签层）所组成。函数的输出可以是一个连续的值（称为回归分析），或是预测一个分类标签（称作分类）。

#### 逻辑回归算法

逻辑回归算法是一个分类算法，通常用在二元分类中(也可以通过一对多策略实现多类别逻辑回归，用于多元分类)，用于估计某种(或多种)事物的可能性，是监督学习的常用算法之一。假设我们要设计一个算法识别某张图片是不是一只猫，逻辑回归算法会输出该图片是猫的概率(由于概率是0-1连续的，因此逻辑回归中有回归二字，但它最终是为了解决分类问题的)。我们可以将图片的RGB通道放入到一个输入向量中，比如图片大小为100\*100，则最终得到长度为3\*100\*100的输入向量x，即x(n)=30000(每张图片的特征维度)。逻辑回归算法对于每个输入向量$x^i$，都应该计算得到对应的预估值$y^i$([0,1])。现在来看看如何设计这个算法，最简单的函数是: $$\hat{y}=w.T*x+b$$ ，其中w为维度为n的列向量，我们用$ \hat{y} $来表示算法得到的预估值，以和训练数据中的已知结果$y$区分，这是典型的线性回归函数(将多维特征映射为单个线性连续值)，在该函数中，$y$取值为负无穷到正无穷，而我们期望的$y$取值为[0,1]。因此我们还需要进行一次转换，一个经典的非线性转换函数是sigmoid函数 $y = \sigma(z) = \frac{1}{(1+e^{-z})}$，其中 $z = w.T*x + b$，这样我们的到$y$值始终限定在0($z$无穷小时)到1($z$无穷大时)之间。现在我们有了一个最简单的逻辑回归算法模型，接下来的任务就是根据训练集的特征和标签，得到最佳的$w$和$b$参数，使得该算法在测试集上的预测准确率变高。

<!--more-->

#### 损失函数和代价函数

现在我们有了$y=\sigma(w.T*x+b)$，对于训练集${(x^{(1)},y^{(1)}),(x^{(2)},y^{(2)})...(x^{(m)},y^{(m)})}$，我们希望算法得到的$\hat{y}^i \approx y^i$，因此对于确定的w和b，我们需要定义一些函数来帮助我们确定这个参数的误差。

损失函数(Lost Function): 也叫误差函数(Error Function)，用于评估算法的误差，即算法得到的$\hat{y}$和实际的$y$的误差有多大，损失函数需要是凸函数，用于后续优化(非凸函数将在梯度下降算法中产生多个局部最优解)，因此像$L(\hat{y},y)=\frac{1}{2}(\hat{y}-y)^2$这种函数不是一个好的误差函数，这里给出一个好的损失函数: $L(\hat{y},y)=-(y\lg\hat{y}+(1-y)\lg(1-\hat{y}))$，当已知事实$y=1$(图片是猫)时，$L(\hat{y},y)=-\lg{\hat{y}}$，即要使误差更小，$\hat{y}$需要尽可能大($\sigma函数极限为1$)，反之，当$y=0$时，$\hat{y}$需要尽可能小，即接近于0。

代价函数(Cost Function): 也叫做整体损失函数，用于检查算法的整体运行情况，即对给定的$w$和$b$，${\hat{y}^{(1)}, \hat{y}^{(2)}...\hat{y}^{(m)}}$和${y^{(1)}, y^{(2)}...y^{(m)}}$误差的平均值，代价函数用符号J表示:

$J(w,b)=\frac{1}{m}\sum_1^mL(\hat{y}^{(i)},y^{(i)})=-\frac{1}{m}\sum_1^m[y^{(i)}\lg\hat{y}^{(i)}+(1-y^{(i)})\lg(1-\hat{y}^{(i)})]$

有了代价函数之后，我们的目标变成了找到合适的参数$w$和$b$，以缩小整体成本$J(w,b)$的值。

#### 梯度下降模型

前面在选择损失函数的时候，提到过凸函数，一个典型地凸函数如下所示:

![](/assets/image/201712/deep-learning-j-w-b.png)

我们的目的就是找到$J(w,b)$值最低时的$w$和$b$值，即图中红色箭头标记的Aim Point。为了找到这个点，我们可以对$w$和$b$初始化任意值，如图中的Init Point点，利用梯度下降模型，每一次参数迭代，我们都调整$w$和$b$的值，以使$J(w,b)$的值更小，如图中标识的方向，逐步地逼近最优解。

梯度下降模型的本质是对每个参数都求偏导数，利用偏导数导数去调整下一步走向，为了简化模型，这里我们只讨论$J(w)$和$w$的关系:

![](/assets/image/201712/deep-learning-j-w.png)

如图，通过不断地迭代$w=w-\alpha dw$即可让$w$的值逐渐逼近于凸函数的最低点，其中$\alpha$称为学习率或步长，用于控制$w$每次的调整幅度。损失函数一定要是凸函数，因为非凸函数会有多个局部最优解(想象为波浪形状)，此时梯度下降算法可能找不到全局最优解。

因此，利用梯度下降算法，我们的参数调整应该是这样的：

$w = w - \alpha * \frac{dJ(w,b)}{dw}$

$b = b - \alpha * \frac{dJ(w,b)}{db}$

#### 对逻辑回归使用梯度下降

现在我们来看看如何求导，目前我们已经知道对于给定的$w$和$b$，如何求得代价函数$J(w,b)$的值，假设输入数据x的维度n=2，则计算流程如下:

![](/assets/image/201712/deep-learning-propagation.png)

这里的$a$即$\hat{y}$(注意和前面的学习步长$\alpha$区分)，图中$\sigma(z)=\frac{1}{(1+e^{-z})}$，$L(a,y)=-(y\lg{a}+(1-y)\lg(1-a))$。整个从参数$w$，$b$推导到损失函数值的过程被称为**正向传播(Forward Propagation)**，而我们现在要做的，是根据损失函数反过来对参数求偏导，这个过程叫**反向传播(Backward Propagation)**:

&emsp; $$ da = \frac{dL}{da} = -\frac{y}{a}+\frac{1-y}{1-a} $$

&emsp; $$ dz = \frac{dL}{dz} = \frac{da}{dz} * \frac{dL(a,y)}{da} = a(1-a) * (-\frac{y}{a}+\frac{1-y}{1-a}) = a - y$$

&emsp; $$ dw_1 = \frac{dL}{dw_1} = \frac{dz}{dw_1} * \frac{dL}{dz} = x_1*dz = x_1(a-y) $$

&emsp; $$ dw_2 = x_2dz = x_2(a-y) $$

&emsp; $$ db = dz = a-y $$

当我们有m个训练数据时，算法迭代看起来像是这样:

J=0; $dw_1$=0; $dw_2$=0; $db$=0;

for i=1 to m:

&emsp; $z^{(i)}$ = $w.T*x^{(i)}+b$

&emsp; $a^{(i)}$ = $\sigma(z^{(i)})$

&emsp; $J$ += $-[y^{(i)}\lg\hat{y}^{(i)}+(1-y^{(i)})\lg(1-\hat{y}^{(i)})] $ 

&emsp; $dz^{(i)}$ = $ a^{(i)} - y^{(i)} $ 

&emsp; $dw_1$ += $x_1*dz^{(i)}$ 

&emsp; $dw_2$ += $x_2*dz^{(i)}$ 

&emsp; $db$ += $dz^{(i)}$

end

J /= m; $dw_1$ /= m; $dw_2$ /= m; $db$ /= m

现在我们得到了$dw_1$, $dw_2$和$db$，就可以结合学习率来引导参数的下一步调整方向，以获得更小的J值:

&emsp; $w_1$ = $w_1$ - $\alpha dw_1$

&emsp; $w_2$ = $w_2$ - $\alpha dw_2$

&emsp; $b$ = $b$ - $\alpha db$

注意到，整个计算过程中，我们会用到三个for循环:

1. 用于迭代迭代训练数据个数m的for循环
2. 用于求$dw_1$，$dw_2$...$dw_n$的循环，上面的例子中n=2
3. 用于迭代梯度下降的for循环，这是最外层的for循环

由于深度学习的训练数据往往是非常大的，因此for循环是很慢的，深度学习之所以能够支撑海量数据，和**向量化(vectoraztion)**技术是分不开的。接下来将讨论如何通过向量化技术去除前面两个for循环。

#### 张量计算加速

在Python中，可以用[numpy](http://www.numpy.org/)包来快速方便地进行张量运算，对于两个百万维度的向量求内积，用`np.dot`函数要比自己用for循环快大概300倍，这得益于numpy充分运用并发和GPU来加速张量运算。

设训练数据的大小为m(即图片的数量)，我们用带括号的上标表示训练数据的索引(即某张图片)，下标表示某个输入向量的索引(即某个RGB值)，然后将每个输入数据x作为列向量，输入数据m作为列数对输入进行矩阵化:

$$
 \left\{
 \begin{matrix}
   x^{(1)}_1 & x^{(2)}_1 & ... & x^{(m)}_1 \\
   x^{(1)}_2 & x^{(2)}_2 & ... & x^{(m)}_2  \\
   ... & ... & ... & ... \\
   x^{(1)}_n & x^{(2)}_n & ... & x^{(m)}_n
  \end{matrix}
  \right\}
$$


此时x的个数称为了输入矩阵的一部分，我们将向量化后得到的输入矩阵称为X，对应的，将向量化后得到的a,z均替换为大写，再结合numpy，整个流程变得简洁且高效:


Z = $w^TX+b$ = np.dot(w.T,X)+b

A = $\sigma(Z)$

$dZ$ = A-Y

$dw$ = $\frac{1}{m}$XdZ.T = np.dot(X, dZ.T)/m

$db$ = $\frac{1}{m}$np.sum(dZ)


### 二. 神经网络

#### 浅层神经网络

我们再来看下逻辑回归算法中的运算模型:

![](/assets/image/201712/1-layer-nn.png)

它实际上是一个只有一层单个神经元的神经网络，在神经网络中，单个神经元通常包含线性函数和激活函数，神经元接收到输入数据，先通过线性回归函数将这些输入与其相应的权重进行乘积运算，再求和得到一个线性输出，这个过程可视为该神经元的内积运算。随后，该线性输出会被送入激活函数。这些激活函数主要是非线性函数，如Sigmoid函数、ReLU函数、Tanh函数等，它们的作用是将线性运算的结果映射到一个通常更适合问题需求的形状或范围，例如：二分类问题中概率介于0与1之间，或者限制输出的范围等。

上图中，输入层L0通常不作为层数，最靠近a的被称为输出层，其它层被称为中间层或隐藏层，我们用`[i]`上标来表示层数，在多层神经网络模型中，$a^{[l]}$是第l层的输出，并且会作为第l+1层的输入，并且我们引入$g^{[l]}$来表示第l层的**激活函数(Activation function)**，在我们的之前的逻辑回归模型中，$g^{[1]}=\sigma(z)$，sigmoid是常用的非线性激活函数之一。

##### 正向传播

如下是一个两层的神经网络:

![](/assets/image/201712/2-layer-nn.png)

在这个神经网络中，L1中一共有四个神经元，也就是会输出$a^{[1]}_1$, $a^{[1]}_2$, $a^{[1]}_3$, $a^{[1]}_4$，同样，为了方便向量化加速，我们通常会将同一层的神经元堆叠起来，用$a^{[1]}$来代替L1层的输出:

&emsp; $$ z^{[1](i)}=w^{[1]T}*x^{(i)}+b^{[1]} $$
&emsp; $$ a^{[1](i)}=g^{[1]}(z^{[1](i)}) $$

其中$w^{[1]}$经堆叠后为(3,4)矩阵(w本身是列向量)，$x^{(i)}$为(3,1)矩阵，$b^{[1]}$为(4,1)，最终$a^{[1]}$为(4,1)，即为L1层的输出，也是L2层的输入:

&emsp; $$ z^{[2](i)}=w^{[2](i)T}*a^{[1](i)}+b^{[2](i)} $$
&emsp; $$ a^{[2](i)}=g^{[2]}(z^{[2](i)}) $$

是的，你可能发现了，这里的上标$^{(l)}$仍然可以像逻辑回归中一样被向量化，所以最终我们的正向传播流程为:

&emsp; $$ Z^{[1]}=W^{[1]}*X+b^{[1]} $$
&emsp; $$ A^{[1]}=g^{[1]}(Z^{[1]}) $$
&emsp; $$ Z^{[2]}=W^{[2]}*A^{[1]}+b^{[2]} $$
&emsp; $$ A^{[2]}=g^{[2]}(Z^{[2]}) $$
&emsp; $$ \hat {Y} = A^{[2]} $$

为了后续描述和计算，我们用$W^{[l]}$替代了$w^{[l]T}$，这里的向量维度分别是: $X$为(3,m)，$W^{[1]}$为(4,3), $b^{[1]}$为(4,1)，$A^{[1]}$为(4,m)，$W^{[2]}$为(1,4)，$b^{[2]}$为(1,1)，$A^{[2]}$为(1,m)。有时候为了方便，我们也可以将输入$X$称作$A^{[0]}$。

注: python [numpy broadcast](https://docs.scipy.org/doc/numpy-1.13.0/user/basics.broadcasting.html)广播机制可以支持维度在运算时扩展，比如$w^{[1]}.T*X+b^{[1]}$中，前者是(4,m)后者是(4,1)，numpy会自动扩展b为(4,m)。

##### 反向传播

现在我们来为两层神经网络选定激活函数:

&emsp; $$ g^{[1]} = tanh(z) = \frac{e^z-e^{-z}}{e^z+e^{-z}} $$ &emsp;&emsp;&emsp; 注: $g^{[1]}\prime = 1-a^2$
&emsp; $$ g^{[2]} = \sigma(z) = \frac{1}{(1+e^{-z})} $$ &emsp;&emsp;&emsp;&emsp; 注: $g^{[2]}\prime = a(1-a)$

现在我们尝试反向传播:

&emsp; $dZ^{[2]}$ = $A^{[2]} - Y$
&emsp; $dW^{[2]}$ = $\frac{1}{m}dZ^{[2]}A^{[1]T}$
&emsp; $db^{[2]}$ = $\frac{1}{m}$np.sum($dZ^{[2]}$)
&emsp; $dZ^{[1]}$ = $W^{[2]}dZ^{[2]}*1-A^{[1]2}））$
&emsp; $dW^{[1]}$ = $\frac{1}{m}dZ^{[1]}X^T$
&emsp; $db^{[1]}$ = $\frac{1}{m}$np.sum(dZ^{[1]})

#### 深度神经网络

前面我们讨论的是一层和两层的神经网络，现在来看看N层的深度神经网络，在深度神经网络中，我们通过$n^{[l]}$来代表第l层的神经元个数，我们知道:

$$ Z^{[l]}=W^{[l]}*A^{[l-1]}+b^{[l]} $$

由于$A^{[l]}$的维数为($n^{[l]}$, m)，$A^{[l-1]}$的维数为($n^{[l-1]}$, m)，因此$W^{[l]}$的维数为($n^{[l]}$, $n^{[l-1]}$)，$b^{[l]}$维数为($n^{[l]}$, 1)。

##### 正向传播和反向传播

我们再来看看深度神经网络的正向传播和反向传播:

![](/assets/image/201712/forward_propagation_backword_propagation.png)

我们可以将传播迭代化:

正向传播:

输入: $A^{[l-1]}$， 输出: $A^{[l]}$

相关公式:

&emsp; $$Z^{[l]} = W^{[l]}A^{[l-1]} + b^{[l]}$$
&emsp; $$A^{[l]} = g^{[l]}(Z^{[l]})$$

反向传播:

输入: $dA^{[l]}$，输出: $dA^{[l-1]}$, $dW^{[l]}$，$db^{[l]}$

相关公式:

&emsp; $$dZ^{[l]} = dA^{[l]}*g^{[l]}\prime(Z^{[l]})$$
&emsp; $$dW^{[l]} = \frac{1}{m}dZ^{[l]}*A^{[l-1]T}$$
&emsp; $$db^{[l]} = \frac{1}{m}$$np.sum($dZ^{[l]}$)
&emsp; $$dA^{[l-1]} = W^{[l]T}*dZ^{[L]}$$

##### 参数和超参数

前面我们反复讨论如何通过反向传播调优参数$W$和$b$，而实际上一个神经网络算法除了这类参数之外，还有一些超参数需要考虑:

1. 学习率/步长 $\alpha$
2. 迭代次数
3. 神经网络的层数L
4. 每层的神经元数$n^{[l]}$
5. 每层激活函数的选择

神经网络的构建本身就是一个不断迭代的过程，根据最初选择的超参数得到一个粗略的模型，然后在此基础上进行训练，但是仍要不断尝试其它超参数以获取更优的网络模型，这个在后面的课程会提到。

### 总结

有了以上理论，我们便可以自己定义一个神经网络(层数L，每层神经元数$n^{[l]}$，激活函数$g^{[l]}$)，根据训练数据X，得到它的误差J，并反过来通过偏导来不断调整每一层的参数以优化这个误差。再辅以向量化这类优化手段，然后"神奇"地发现，整个系统开始工作了。深度学习属于这个时代的黑魔法，已经在语音识别，计算机视觉，自然语言处理等多个领域有了非常成熟的应用，至于机器是否真的能通过神经网络，达到向人一样思考这个且不讨论，就目前而言，深度学习的理论基础还是比较欠缺，比如激活函数的选取，为什么神经网络能有效运转，应该定义多大的神经网络等等。正如课程作者Andrew Ng所言，深度学习的研究，仍然处于初级阶段，很多时候都需要不断地尝试与对比，比如过段就换一次超参数。最后，非常推荐大家上Coursera学习这门课程，毕竟绝大部分时候，我们都在用机器的思维来思考和构建程序，而深度学习是让尝试机器像人一样思考和学习。这本身就是一件很有意思的事情。