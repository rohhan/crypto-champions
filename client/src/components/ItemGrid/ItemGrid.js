import React from 'react';
import { ItemGridTile } from '../ItemGridTile/ItemGridTile';
import './ItemGrid.css';

const defaultRenderItem = (item, isSelectable) => (
    <ItemGridTile
        itemImage={item.image}
        itemLabel={item.label}
        isSelectable={isSelectable}
        isSelected={item.isSelected}
        itemSublabel={item.subLabel}
    />
);

export const ItemGrid = ({ items = [], onSelect, renderItem = defaultRenderItem }) => {
    return (
        <div className="item-grid">
            {items.map((item) => {
                const handleOnClick = () => item.isSelectable && onSelect && onSelect(item);
                return (
                    <div className="item-grid__item" key={item.id} onClick={handleOnClick}>
                        {renderItem(item, !!onSelect && item.isSelectable)}
                    </div>
                );
            })}
        </div>
    );
};
