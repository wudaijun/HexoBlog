
python2.7.6

### Python对象

#### 对象

所有Python对象的三个属性：

- id: 相当于对象地址，用于标识一个对象。通过`id(obj)`查看。程序很少用到，但对理解对象值语义有帮助
- type: 对象类型，通过`type(obj)`查看
- value: 对象的值

#### 类型

在Python2.2之后，统一了类型(type)和类(class)，这意味着，所有的内建类型和自定义的类是一样的。`int(5.0)`不是内建函数，而是构造函数。并且你可以基于标准类型(如int)派生。

在Python中，类型和类本身也是一个对象，它保存类的属性，方法等。即`type(5)`返回一个对象，它的类型是type：

```python
>>> type(5)
<type 'int'>
>>> type(type(5))
<type 'type'>
>>> type(type(type(5)))
<type 'type'>
```

#### 值语义

Python中的类型分为可变类型和不可变类型：

- 可变类型: 列表，字典
- 不可变类型: 数字，字符串，元组

从类C的思想来理解，可变类型传递的是引用，不可变类型传递的是值，但在Python中传递的都是引用，只不过如果对不可变类型变量更改，将会触发拷贝(和Erlang不可变语义类似)。在Python中，想对可变类型进行值拷贝，可通过`copy.copy(obj)`或`copy.deepcopy(obj)`实现。

```python
# 对不可变类型的赋值实际上也是传递引用
>>> a=b=5000
>>> id(a)==id(b)
True
```

针对小型常用对象的优化:

```python
>>> a = 5
>>> b = 5
>>> id(a)==id(b)
True
>>> c=5.0
>>> d=5.0
>>> id(c)==id(d)
False
>>> e = 5000
>>> f = 5000
>>> id(e) == id(f)
False
```
理解上述结果的关键在于在Python中，小范围整数和字符串是会被缓存的(类似于常量池)，因此a,b指向同一个对象。

### 面向对象

由于Python中的类(类型)也是对象(类型为type)，因此Python的面向对象对其它任何语言都纯粹而有趣。

#### 理解类

在主流OOP语言(C++,Java)中，


先认识一下Python对象，Python对象属性分为三个部分：

- 用户定义的属性
- 特定类型Python对象固有的特殊属性
- 所有Python对象共有的特殊属性

```python
class A:
    x = 1
    def __init__(self):
        self.x = 2
        self.y = 3
        
     

if __name__ == "__main__":
    a = A()
    print(A.__dict__)
    print(a.__dict__)
    
# Output
{'x': 1, '__module__': '__main__', '__doc__': None, '__init__': <function __init__ at 0x10517b230>}
{'y': 3, 'x': 2}
```

在上例中，可通过`__dict__()`来查看对象中用户自定义的属性(对type对象来说，包含用户定义的函数)和部分特定类型的特殊属性(`__module__`和`__doc__`属于type对象的特殊属性)，而`__dict__()`函数本身，是所有对象共有的特殊属性。

对类型A来说，它作为一个type对象保存了类中的数据属性，类方法

   
特殊属性
构造时机 __new__ __init__
引用析构
类属性和实例属性的混写




