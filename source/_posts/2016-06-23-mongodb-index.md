---
title: MongoDB 索引
layout: post
categories: database
tags: mongodb

---

MongoDB的索引和传统关系数据库的索引几乎一致，绝大多数优化关系数据库索引的技巧同样适用于MongoDB。

MongoDB的索引操作：

    db.collection.createIndex(keys, opts)
    db.collection.getIndexes()
    db.collection.dropIndex(index)
    db.collection.dropIndexes()

MongoDB为每个集合默认创建{'_id':1}的索引
