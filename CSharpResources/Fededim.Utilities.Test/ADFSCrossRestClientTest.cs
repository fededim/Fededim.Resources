namespace Fededim.Utilities.Test
{
    public class UnitTests
    {
        /// <summary>
        /// Tests login method, need to find a free ADFS server to test somewhere
        /// </summary>
        /// <returns></returns>
        [Fact]
        public async Task TestADFSRestClient_Login()
        {
            var adfsClient = new ADFSCrossRestClient("url", "domain\\user", "password");

            await adfsClient.Login();
        }
    }
}
