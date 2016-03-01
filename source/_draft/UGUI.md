

UGUI

所有的UI元素都必须存在于画布(Canvas)之上。

Canvas Group


### 画布的渲染：

Screen Space - Overlay

Canvas使用屏幕空间，始终在场景的最上层进行渲染，并且随屏幕大小变化而自适应。

Screen Space - Camera

Canvas使用摄像机空间，将Canvas与指定摄像机关联，Canvas将只被该摄像机渲染，摄像机的渲染设置将影响到Canvas渲染，其它与Screen Space - Overlay一致。

World Space

Canvas将与场景中的其它任何游戏对象一样，属于3D场景的一部分。

Canvas上的元素绘制顺序和其在Hierarchy上的顺序一致，后绘制的元素将覆盖先绘制的元素，可通过SetAsFirstSibling,SetAsLastSibling,SetSiblingIndex修改绘制顺序

### 画布的布局

画布使用Rect Transfrom，在传统Transform之上，添加了高度和宽度，放大/缩放操作将影响高度和宽度，而不作用于scale，因此Transform的scale字段对画布并没有意义(画布没有模型)。

锚点：

Rect Transform伴随一个锚点(anchor)的概念，锚点将UI元素的Rect Transform的四个角绑定在画布上，用于控制UI元素相对于画布或其父元素的布局，这样随着画布的放大/缩放，UI元素能够进行一定程度地自适应(比如，始终处于画布中心，离左下角固定距离等)。

