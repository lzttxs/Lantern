//
//  LanternView.swift
//  Lantern
//
//  Created by JiongXing on 2019/11/14.
//  Copyright © 2021 Shenzhen Hive Box Technology Co.,Ltd All rights reserved.
//

import UIKit

open class LanternView: UIView, UIScrollViewDelegate {
    
    /// 弱引用lantern
    open weak var lantern: Lantern?
    
    /// 询问当前数据总量
    open lazy var numberOfItems: () -> Int = { 0 }
    
    /// 返回可复用的Cell类。用户可根据index返回不同的类。本闭包将在每次复用Cell时实时调用。
    open lazy var cellClassAtIndex: (_ index: Int) -> LanternCell.Type = { _ in
        LanternImageCell.self
    }
    
    /// 刷新Cell数据。本闭包将在Cell完成位置布局后调用。
    open lazy var reloadCellAtIndex: (Lantern.ReloadCellContext) -> Void = { _ in }
    
    /// 自然滑动引起的页码改变时回调
    open lazy var didChangedPageIndex: (_ index: Int) -> Void = { _ in }
    
    /// Cell将显示
    open lazy var cellWillAppear: (LanternCell, Int) -> Void = { _, _ in }
    
    /// Cell将不显示
    open lazy var cellWillDisappear: (LanternCell, Int) -> Void = { _, _ in }
    
    /// Cell已显示
    open lazy var cellDidAppear: (LanternCell, Int) -> Void = { _, _ in }
    
    /// 滑动方向
    open var scrollDirection: Lantern.ScrollDirection = .horizontal
    
    /// 项间距
    open var itemSpacing: CGFloat = 30
    
    /// 当前页码。给本属性赋值不会触发`didChangedPageIndex`闭包。
    open var pageIndex = 0 {
        didSet {
            if pageIndex != oldValue {
                isPageIndexChanged = true
            }
        }
    }
    
    /// 页码是否已改变
    public var isPageIndexChanged = true
    
    /// 容器
    open lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.backgroundColor = .clear
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.isPagingEnabled = true
        sv.isScrollEnabled = true
        sv.delegate = self
        if #available(iOS 11.0, *) {
            sv.contentInsetAdjustmentBehavior = .never
        }
        return sv
    }()
    /// 新增更多num之前的数据总量
    open var lastNumberOfItems: Int = 0
    
    /// 是否旋转
    var isRotating = false
    
    deinit {
        LanternLog.high("deinit - \(self.classForCoder)")
    }
    
    public convenience init() {
        self.init(frame: .zero)
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    open func setup() {
        backgroundColor = .clear
        addSubview(scrollView)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        let height = scrollView.frame.size.height
        let width = scrollView.frame.size.width
        
        if scrollDirection == .horizontal {
            scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width + itemSpacing, height: bounds.height)
        } else {
            scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + itemSpacing)
        }
        
        //避免重复刷新数据
        if height != scrollView.frame.size.height || width != scrollView.frame.size.width {
            reloadData()
        }
    }
    
    open func resetContentSize() {
        let maxIndex = CGFloat(numberOfItems())
        if scrollDirection == .horizontal {
            scrollView.contentSize = CGSize(width: scrollView.frame.width * maxIndex,
                                            height: scrollView.frame.height)
        } else {
            scrollView.contentSize = CGSize(width: scrollView.frame.width,
                                            height: scrollView.frame.height * maxIndex)
        }
    }
    
    /// 刷新数据，同时刷新Cell布局
    open func reloadData() {
        // 修正pageIndex，同步数据源的变更
        pageIndex = max(0, pageIndex)
        pageIndex = min(pageIndex, numberOfItems())
        resetContentSize()
        resetCells()
        layoutCells()
        reloadItems()
        refreshContentOffset()
    }
    
    /// 根据页码更新滑动位置
    open func refreshContentOffset() {
        // 针对无限新增图片数据，scrollView的contentOffset会偏移问题判断处理
        if pageIndex == lastNumberOfItems {
            return
        }
        if scrollDirection == .horizontal {
            scrollView.contentOffset = CGPoint(x: CGFloat(pageIndex) * scrollView.bounds.width, y: 0)
        } else {
            scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(pageIndex) * scrollView.bounds.height)
        }
    }
    
    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 屏幕旋转时会触发本方法。此时不可更改pageIndex
        if isRotating {
            resetCells()
            layoutCells()
            reloadItems()
            isRotating = false
            return
        }
        
        if scrollDirection == .horizontal && scrollView.bounds.width > 0  {
            pageIndex = Int(round(scrollView.contentOffset.x / (scrollView.bounds.width)))
        } else if scrollDirection == .vertical && scrollView.bounds.height > 0 {
            pageIndex = Int(round(scrollView.contentOffset.y / (scrollView.bounds.height)))
        }
        if isPageIndexChanged {
            isPageIndexChanged = false
            resetCells()
            layoutCells()
            reloadItems()
            didChangedPageIndex(pageIndex)
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if let cell = visibleCells[pageIndex] {
            cellDidAppear(cell, pageIndex)
        }
    }
    
    //
    // MARK: - 复用Cell
    //
    
    /// 显示中的Cell
    open var visibleCells = [Int: LanternCell]()
    
    /// 缓存中的Cell
    open var reusableCells = [String: [LanternCell]]()
    
    /// 入队
    private func enqueue(cell: LanternCell) {
        let name = String(describing: cell.classForCoder)
        if var array = reusableCells[name] {
            array.append(cell)
            reusableCells[name] = array
        } else {
            reusableCells[name] = [cell]
        }
    }
    
    /// 出队，没缓存则新建
    private func dequeue(cellType: LanternCell.Type, browser: Lantern) -> LanternCell {
        var cell: LanternCell
        let name = String(describing: cellType.classForCoder())
        if var array = reusableCells[name], array.count > 0 {
            LanternLog.middle("命中缓存！\(name)")
            cell = array.removeFirst()
            reusableCells[name] = array
        } else {
            LanternLog.middle("新建Cell! \(name)")
            cell = cellType.generate(with: browser)
        }
        return cell
    }
    
    /// 重置所有Cell的位置。更新 visibleCells 和 reusableCells
    open func resetCells() {
        guard let browser = lantern else {
            return
        }
        var removeFromVisibles = [Int]()
        for (index, cell) in visibleCells {
            //修复重复移除添加问题
            if index == pageIndex || index == pageIndex - 1 || index == pageIndex + 1  {
                if index != pageIndex {
                    cellWillDisappear(cell, index)
                }
                continue
            }
            cellWillDisappear(cell, index)
            cell.removeFromSuperview()
            enqueue(cell: cell)
            removeFromVisibles.append(index)
        }
        removeFromVisibles.forEach { visibleCells.removeValue(forKey: $0) }
        
        // 添加要显示的cell
        let itemsTotalCount = numberOfItems()
        for index in (pageIndex - 1)...(pageIndex + 1) {
            if index < 0 || index > itemsTotalCount - 1 {
                continue
            }
            //修复重复移除添加问题
            if visibleCells[index] != nil {
                continue
            }
            let clazz = cellClassAtIndex(index)
            LanternLog.middle("Required class name: \(String(describing: clazz))")
            LanternLog.middle("index:\(index) 出列!")
            let cell = dequeue(cellType: clazz, browser: browser)
            visibleCells[index] = cell
            scrollView.addSubview(cell)
            //修复重复移除添加问题
            reloadCellAtIndex((cell, index, pageIndex))
            cell.setNeedsLayout()
        }
    }
    
    /// 刷新所有显示中的Cell位置
    open func layoutCells() {
        let cellWidth = bounds.width
        let cellHeight = bounds.height
        for (index, cell) in visibleCells {
            if scrollDirection == .horizontal {
                cell.frame = CGRect(x: CGFloat(index) * (cellWidth + itemSpacing), y: 0, width: cellWidth, height: cellHeight)
            } else {
                cell.frame = CGRect(x: 0, y: CGFloat(index) * (cellHeight + itemSpacing), width: cellWidth, height: cellHeight)
            }
        }
    }
    
    /// 刷新所有Cell的数据
    open func reloadItems() {
        //修复重复移除添加问题并重复reload的问题
//        visibleCells.forEach { [weak self] index, cell in
//            guard let `self` = self else { return }
//            self.reloadCellAtIndex((cell, index, self.pageIndex))
//            cell.setNeedsLayout()
//        }
        if let cell = visibleCells[pageIndex] {
            cellWillAppear(cell, pageIndex)
        }
    }
}
