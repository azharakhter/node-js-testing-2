// app.js
import express from 'express';

const app = express();
const port = 3000;

// Route for addition
app.get('/add', (req, res) => {
    const { a, b } = req.query;
    const sum = Number(a) + Number(b);
    res.send(`Sum is: ${sum}`);
});

// Root route
app.get('/', (req, res) => {
    res.send('Hello from Node.js Server!');
});

// Start server
app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
});
