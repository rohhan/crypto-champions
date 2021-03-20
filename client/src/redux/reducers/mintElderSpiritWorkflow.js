import { SET_ELDER_CLASS, SET_ELDER_RACE, SET_ELDER_STONE } from '../actions';

const initialState = {
    stone: null,
    race: null,
    elderClass: null
};

export const mintElderSpiritWorkflow = (state = initialState, action) => {
    switch (action.type) {
        case SET_ELDER_STONE:
            return {
                ...state,
                stone: action.stone
            };
        case SET_ELDER_RACE:
            return {
                ...state,
                race: action.race
            };
        case SET_ELDER_CLASS:
            return {
                ...state,
                elderClass: action.elderClass
            };
        default:
            return state;
    }
};