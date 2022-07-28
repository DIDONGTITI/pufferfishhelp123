// const Card = require('./src/_includes/components/Card');

module.exports = function (eleventyConfig) {
    // Keeps the same directory structure.
    eleventyConfig.addPassthroughCopy("src/assets/");
    eleventyConfig.addPassthroughCopy("src/img");
    eleventyConfig.addPassthroughCopy("src/css");
    eleventyConfig.addPassthroughCopy("src/js");
    eleventyConfig.addPassthroughCopy("src/contact");
    eleventyConfig.addPassthroughCopy("src/app-demo");
    // eleventyConfig.addPassthroughCopy({"../blog":"../src/blog"});

    eleventyConfig.addCollection('posts', function (collection) {
        return collection.getFilteredByGlob('src/blog/*.md');
    });

    eleventyConfig.addWatchTarget("src/css");
    eleventyConfig.addWatchTarget("markdown/");
    eleventyConfig.addWatchTarget("components/Card.js");

    // eleventyConfig.addShortcode("Card",Card);

    return {
        dir: {
            input: 'src',
            includes: '_includes',
            output: '_site',
        },
        templateFormats: ['md', 'njk', 'html'],
        markdownTemplateEngine: 'njk',
        htmlTemplateEngine: 'njk',
        dataTemplateEngine: 'njk',
    };
};