// test/app.test.js
import { expect } from 'chai';
import add from '../app.js';

describe('Addition function', () => {
    it('should return the sum of two numbers', () => {
        const result = add(2, 3);
        expect(result).to.equal(5);
    });
});
