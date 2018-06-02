---
title: React - Web中的函数式思维
layout: post
categories: web 
tags:
- react
- web
---

### 预备知识

[ES6](http://es6.ruanyifeng.com/): Javascript 的新标准，主要包括引入class，箭头函数，let, const 新关键字等。

[JSX](https://doc.react-china.org/docs/introducing-jsx.html): JSX 是JavaScript 语法扩展，让在 js 中写HTML像模板语言一样方便，最终会编译为js。

### React 特性

#### 1. 组件

React的核心思想便是将UI切分成一些的独立的、可复用的组件，这样你就只需专注于构建每一个单独的部件，达到非常灵活的组件级别的解耦和复用。

<!--more-->

组件本质上是函数(ES6的 class仍然基于之前的function prototype实现)，接收任意值，并返回一个 React 元素。组件可以像HTML标签一样被使用:

    // 组件本身，接收 props，返回界面显示元素
    function Welcome(props) {
      return <h1>Hello, {props.name}</h1>;
    }
    
    // 使用Welcome组件提供的 k-v 对将作为props参数(property的缩写)
    // 其实本质上就是HTML标签的attribute)传入 Welcome 组件
    const element = <Welcome name="Sara" />;
    ReactDOM.render(
      element,
      document.getElementById('root')
    );

上面的组件被称为无状态组件，有状态(state)的组件通常通过 class 实现，通过 render 方法返回界面元素:

    class Clock extends React.Component {
      constructor(props) {
        super(props);
        this.state = {date: new Date()};
      }
    
      componentDidMount() {
        this.timerID = setInterval(
          () => this.tick(),
          1000
        );
      }
    
      componentWillUnmount() {
        clearInterval(this.timerID);
      }
    
      tick() {
        this.setState({
          date: new Date()
        });
      }
    
      render() {
        return (
          <div>
            <h1>Hello, world!</h1>
            <h2>It is {this.state.date.toLocaleTimeString()}.</h2>
          </div>
        );
      }
    }
    
    ReactDOM.render(
      <Clock />,
      document.getElementById('root')
    );

[CodePen预览](https://codepen.io/gaearon/pen/amqdNA?editors=0010)

简单来说，组件就是将props和state映射为React 元素。比如 props 可能是一批库存列表，state 可能包含是否勾选了显示无货商品的复选框，然后组件结合这两部分信息，生成对应的 React 元素。

props对于组件来说是只读的，其字段映射到外部使用该组件时传入的属性(除了 props.children，它代表该组件下定义的所有的子节点)，属性值可以是基础数据类型，回调函数，甚至 React 元素，因此，组件还可以通过提供 propTypes 来验证外部使用组件传入的属性是否符合规范。

state仅由其所属组件维护，通常是一些和界面显示相关的内部状态(比如是否勾选复选项)，通过`this.setState`可变更这些状态。React 会追踪这些状态变更并反映到虚拟DOM上，开发者无需关心何时更新虚拟DOM并反馈到真实DOM上，React 可能会将几次setState操作merge为一个来提高性能，用官方的说法，setState是异步更新的。

元素是 React应用的最小单位，React 当中的元素事实上是普通的对象，比如`const element = <h1>Hello, world</h1>;`。React DOM 可以确保 浏览器 DOM 的数据内容与 React 元素保持一致。

每个组件都有自己的生命周期，通过生命周期钩子实现，如componentDidMount，componentWillUnMount等。

#### 2. 虚拟 DOM

组件并不是真实的 DOM 节点，而是存在于内存之中的一种数据结构，叫做虚拟 DOM）。只有当它插入文档以后，才会变成真实的 DOM 。根据 React 的设计，所有的 DOM 变动，都先在虚拟 DOM 上发生，然后再将实际发生变动的部分，反映在真实 DOM上，这种算法叫做 [DOM Diff][] ，它可以极大提高网页的性能表现。

React 中所有的组件被组织为一棵树（虚拟 DOM 树），React将界面视为一个个特定时刻的固定内容（就像一帧一帧的动画），而不是随时处于变化之中（而不是处于变化中的一整段动画）。每个组件只关心如何根据数据(props)和状态(state)得到React元素(element)。而不关心自己何时被渲染，是否需要渲染等细节。React 会在组件的 props 和 state 变更时知晓状态变更，并负责调用render进行渲染(像是"桢驱动")。如此，组件只负责维护状态和映射，其它的事情(驱动，渲染，优化)React 都帮你做好了。由于 DOM Diff 算法的存在，React会先比较虚拟DOM的差异，在真实 DOM 中只会渲染改变了的部分。

#### 3. DOM Diff

DOM Diff的用于比较新旧虚拟DOM树，找到最少的转换步骤。这本是O(n^3)的复杂度，React使用启发式算法，复杂度仅为O(n)。这归功于React对Web界面作出的两个假设:

1. 两个不同类型的元素将产生不同的树。
2. 通过渲染器附带key属性，开发者可以示意哪些子元素可能是稳定的。

在实际 Diff 过程中，React只会对同一层次的节点进行比较，如果节点类型不同或者被移动到不同层级，则整个节点(及其子节点)重新插入到真实DOM中。如果节点类型相同，则依靠开发者提供的key属性来优化列表比较。

因此在实际应用中，保持稳定的 DOM 结构，合理使用key属性可以帮助 React 更好的完成 diff 操作。

另外，组件的生命周期(生命周期钩子)其实也跟 DOM Diff 有关。

#### 4. 单向数据流

理想情况下，React组件是单向数据流的，任何状态始终由对应组件所有，并且从该状态导出的任何数据或 UI 只能影响树中下方的组件。即整个数据流是从父组件到子组件的。在实际应用中，组件交互往往会更复杂，React 也提供了一些最佳实践:

- 组合而不是继承: 父子组件通过组合而不是继承的方式来实现
- 子组件更新父组件: 父组件将自己的回调函数通过 props 传给子组件
- 兄弟组件需要共享状态: 将状态提升到其共有的父组件中，或者通过[Context][]
- 高阶组件: 参数(props)和返回值都是组件的无状态函数，可以完成对组件更高层次的行为模式抽象，[参考](https://doc.react-china.org/docs/higher-order-components.html)

### 总结

俗话说，没有什么是加一层抽象不能解决的，React虚拟DOM，就像操作系统的虚拟内存等概念一样，极大程度简化了开发者负担。虚拟内存屏蔽了内存换入换出等细节，而虚拟DOM屏蔽了何时渲染，渲染优化等问题，开发只关心架设好虚拟DOM，然后随着状态变更，真实DOM会随时更新。

React另一个很棒的想法是将界面看作一帧桢的动画，当前状态决定当前界面，React组件本质上就是将局部状态映射为局部界面(动画某一帧的某一部分)，然后组装为整个UI界面(某一帧的定格)。这其中外部输入(props)是只读的，内部状态(state)是可变的，而输出的界面元素(element)是不可变的。

React 在很多地方都有函数式的影子，比如数据流思想(处理过程输入输出都不可变)，高阶组件(其实就是高阶函数)等，这种思想让开发者理解和调试变得简单，开发者只关心props+state=>element 的映射，React来处理其它的实现细节，如虚拟DOM，DOM Diff(有点像函数式语言实现不可变语义的Copy-On-Write)，以及虚拟DOM到真实DOM的映射等。

React的单向数据流，是一种非常简单和理想化的模型，虽然有回调函数，高阶组件等方法，但不可避免地，React 也提供了类似 Context 这种全局上下文的概念。这和函数式一样，理念在实践中只是原则而不是规则。


[Dom Diff]: http://www.infoq.com/cn/articles/react-dom-diff
[Context]: https://doc.react-china.org/docs/context.html

