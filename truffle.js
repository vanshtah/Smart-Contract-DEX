module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8500,
      network_id: "3", // Match any network id
      gas: 7984452, // Block Gas Limit same as latest on Mainnet https://ethstats.net/
      gasPrice: 2000000000, // same as latest on Mainnet https://ethstats.net/
      // Mnemonic: "copy obey episode awake damp vacant protect hold wish primary travel shy"
      from: "0x2602302Bb7B2D6E94a8f9A9140C27d42C72F3ED3"
    }
  }
};
