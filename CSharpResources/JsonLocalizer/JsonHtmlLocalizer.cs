using Microsoft.AspNetCore.Mvc.Localization;
using Microsoft.Extensions.Localization;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace JsonLocalizer
{
    public class JsonHtmlLocalizer<T>: IHtmlLocalizer<T>
    {
        private readonly IStringLocalizer<T> _localizer;

        public JsonHtmlLocalizer(IStringLocalizer<T> localizer)
        {
            _localizer = localizer ?? throw new ArgumentNullException(nameof(localizer));
        }

        public LocalizedHtmlString this[string name] => ToHtmlString(_localizer[name]);

        public LocalizedHtmlString this[string name, params object[] arguments] => ToHtmlString(_localizer[name], arguments);

        public IEnumerable<LocalizedString> GetAllStrings(bool includeParentCultures)
        {
            return _localizer.GetAllStrings(includeParentCultures);
        }

        public LocalizedString GetString(string name) 
        {
            if (name == null)
            {
                throw new ArgumentNullException(nameof(name));
            }

            return _localizer[name];
        }

        public LocalizedString GetString(string name, params object[] arguments)
        {
            if (name == null)
            {
                throw new ArgumentNullException(nameof(name));
            }

            return _localizer[name,arguments];
        }

        public IHtmlLocalizer WithCulture(CultureInfo culture)
        {
            return this;
        }


        /// <summary>
        /// Creates a new <see cref="LocalizedHtmlString"/> for a <see cref="LocalizedString"/>.
        /// </summary>
        /// <param name="result">The <see cref="LocalizedString"/>.</param>
        protected virtual LocalizedHtmlString ToHtmlString(LocalizedString result) =>  new LocalizedHtmlString(result.Name, result.Value, result.ResourceNotFound);

        protected virtual LocalizedHtmlString ToHtmlString(LocalizedString result, object[] arguments) => new LocalizedHtmlString(result.Name, result.Value, result.ResourceNotFound, arguments);
    }
}
